# BCrypt Tool

This is a tiny tool along the same lines as https://github.com/bitnami/bcrypt-cli to enable hashing of a cleartext password with bcrypt on the commandline. The bitnami tool didn't work for our initial use case, as it was incompatible with the salting mechanism used by NiFi for its internal password storage.

Most common use case will be in init containers to hash cleartext passwords from Kubernetes secrets and replace these in config files.

The tool reads from stdin.

## Building

    mvn package

## Usage

````
➜  echo password | java -jar stackable-bcrypt-1.0-SNAPSHOT-jar-with-dependencies.jar
$2b$12$esbe7T2nhgkk5hwu2jM4Kuo9RQ4Zwjdl5a6Ir9/gILUJ4swHbZYrK
````

