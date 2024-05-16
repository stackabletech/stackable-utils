#!/usr/bin/env python

import json
import os
import re
import sys
import warnings
import pandas as pd
from adbc_driver_postgresql import dbapi

PURL_MAVEN_REGEX = re.compile('pkg:maven/([^/]+)/.+')
DB_HOSTNAME = "db.stackable.tech"
DB_PORT = 5432
DB_NAME = "features"

scan_result_json_file = sys.argv[1]
db_username = os.environ['STACKABLE_DB_USERNAME']
db_password = os.environ['STACKABLE_DB_PASSWORD']


def prepend_maven_package(row):
    package_name = row['package_name']
    match = PURL_MAVEN_REGEX.match(row['purl'])
    if match:
        maven_package = match.group(1)
        return f"{maven_package}:{package_name}"
    return package_name


def severity_metrics(dataframe, severity_field):
    high_count = (
        sum(dataframe[severity_field] == "Critical")
        + sum(dataframe[severity_field] == "High"))
    medium_count = sum(dataframe[severity_field] == "Medium")
    low_count = sum(dataframe[severity_field] == "Low")
    unknown_count = (
        len(dataframe.index)
        - high_count
        - medium_count
        - low_count)

    return [
        f'{high_count}',
        f'{medium_count}',
        f'{low_count}',
        f'{unknown_count}']


# Load NeuVector scan results

with open(scan_result_json_file, mode='r', encoding='utf-8') as f:
    scan_result = json.load(f)

# Determine image

registry = scan_result['report']['registry'].removeprefix('https://')
repository = scan_result['report']['repository']
tag = scan_result['report']['tag'].removesuffix('-amd64')
image = f"{registry}/{repository}:{tag}"

# List vulnerabilities

raw_vulnerabilities = scan_result['report']['vulnerabilities']
vulnerabilities = (
    pd
    .json_normalize(raw_vulnerabilities)
    .filter(items=[
        'name',
        'package_name',
        'package_version',
        'severity',
        'score',
        'score_v3',
        'description',
        'file_name',
        'fixed_version',
        'link'])
    .set_index([
        'package_name',
        'package_version',
        'name']))

# Load all observations

# Ignore the following warning:
# UserWarning: pandas only supports SQLAlchemy connectable
# (engine/connection) or database string URI or sqlite3 DBAPI2
# connection. Other DBAPI2 objects are not tested. Please consider using
# SQLAlchemy.
warnings.simplefilter(action='ignore', category=UserWarning)
db_url = (
    'postgres://'
    f'{db_username}:{db_password}@'
    f'{DB_HOSTNAME}:{DB_PORT}/'
    f'{DB_NAME}')
with dbapi.connect(db_url) as conn:
    assessments = pd.read_sql(
        f"""
        SELECT
            vulnerability_id AS name,
            origin_component_name AS package_name,
            origin_component_version AS package_version,
            origin_component_purl AS purl,
            assessment_severity,
            current_status AS status,
            current_vex_justification AS justification
        FROM secobserve.core_observation
        WHERE origin_docker_image_name_tag = '{image}'
        """,
        conn)
warnings.simplefilter('always')

if len(assessments.index):
    assessments['package_name'] = \
        assessments.apply(prepend_maven_package, axis=1)
else:
    print(f"No observations found for {image}", file=sys.stderr)

assessments.drop(columns=['purl'], inplace=True)
assessments.set_index([
        'package_name',
        'package_version',
        'name'],
    inplace=True)

# Merge vulnerabilities and observations

affected = vulnerabilities.join(assessments)
affected = affected[affected['status'] != "Not affected"]
affected['final_severity'] = (
    affected.assessment_severity
    .replace("", None)
    .fillna(affected.severity))

print(",".join(
    [f"{image}", ""] +
    severity_metrics(vulnerabilities, 'severity') +
    [""] +
    severity_metrics(affected, 'final_severity')))
