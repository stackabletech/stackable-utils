#!/usr/bin/env python

import json
import pandas as pd
import re
import sys

purl_maven_regex = re.compile('pkg:maven/([^/]+)/.+')

def prepend_maven_package(row):
    package_name = row['package_name']
    match = purl_maven_regex.match(row['purl'])
    if match:
        maven_package = match.group(1)
        return f"{maven_package}:{package_name}"
    else:
        return package_name


def metrics(df):
    high_count = sum(df['severity'] == "High")
    medium_count = sum(df['severity'] == "Medium")
    low_count = sum(df['severity'] == "Low")
    unknown_count = len(df.index) - high_count - medium_count - low_count

    return [f'{high_count}', f'{medium_count}', f'{low_count}', f'{unknown_count}']


# Load NeuVector scan results

scan_result_json_file = sys.argv[1]

with open(scan_result_json_file, 'r') as f:
    scan_result = json.load(f)

# Determine image

registry = scan_result['report']['registry'].removeprefix('https://')
repository = scan_result['report']['repository']
# TODO Remove removesuffix after rescanning
tag = scan_result['report']['tag'].removesuffix('-amd64')
image = f"{registry}/{repository}:{tag}"

# List vulnerabilities

raw_vulnerabilities = scan_result['report']['vulnerabilities']
vulnerabilities = (pd
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
    .set_index(['package_name', 'package_version', 'name']))

# Load all observations

all_observations_operators = pd.read_csv('all_observations_operators.csv', low_memory=False)
all_observations_products = pd.read_csv('all_observations_products.csv', low_memory=False)
all_observations = pd.concat([all_observations_operators, all_observations_products])
image_observations = all_observations[all_observations['Origin docker image name tag'] == image]
assessments = (image_observations
    .filter(items=[
        'Vulnerability id',
        'Origin component name',
        'Origin component version',
        'Origin component purl',
        'Current status',
        'Current vex justification'])
    .rename(columns={
        'Vulnerability id': 'name',
        'Origin component name': 'package_name',
        'Origin component version': 'package_version',
        'Origin component purl': 'purl',
        'Current status': 'status',
        'Current vex justification': 'justification'}))
if len(assessments.index):
    assessments['package_name'] = assessments.apply(prepend_maven_package, axis=1)
assessments.drop(columns=['purl'], inplace=True)
assessments = assessments.set_index(['package_name', 'package_version', 'name'])

# Merge vulnerabilities and observations

affected = vulnerabilities.join(assessments)
affected = affected[affected['status'] != "Not affected"]

print(",".join([f"{image}", ""] + metrics(vulnerabilities) + [""] + metrics(affected)))
