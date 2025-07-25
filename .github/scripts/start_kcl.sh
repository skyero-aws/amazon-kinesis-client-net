#!/bin/bash
set -e
set -o pipefail

# Reset the values of checkpoint, leaseCounter, ownerSwitchesSinceCheckpoint, and leaseOwner in DynamoDB table
echo "Resetting checkpoint for shardId-000000000000"
aws dynamodb update-item \
  --table-name $APP_NAME \
  --key '{"leaseKey": {"S": "shardId-000000000000"}}' \
  --update-expression "SET checkpoint = :checkpoint, leaseCounter = :counter, ownerSwitchesSinceCheckpoint = :switches, leaseOwner = :owner" \
  --expression-attribute-values '{
    ":checkpoint": {"S": "TRIM_HORIZON"},
    ":counter": {"N": "0"},
    ":switches": {"N": "0"},
    ":owner": {"S": "AVAILABLE"}
  }' \
  --return-values NONE 2>/dev/null || echo "DynamoDB table not found or update failed - KCL will create it"

# Get records from stream to verify they exist before continuing
SHARD_ITERATOR=$(aws kinesis get-shard-iterator --stream-name $STREAM_NAME --shard-id shardId-000000000000 --shard-iterator-type TRIM_HORIZON --query 'ShardIterator' --output text)
INITIAL_RECORDS=$(aws kinesis get-records --shard-iterator $SHARD_ITERATOR)
RECORD_COUNT_BEFORE=$(echo $INITIAL_RECORDS | jq '.Records | length')

echo "Found $RECORD_COUNT_BEFORE records in stream before KCL start"

if [[ "$RUNNER_OS" == "macOS" ]]; then
  brew install coreutils
  (cd SampleConsumer && gtimeout 300 dotnet run --project ../Bootstrap/Bootstrap.csproj --properties kcl.properties --execute 2>&1 | tee ../kcl_output.log) || [ $? -eq 124 ]
elif [[ "$RUNNER_OS" == "Linux" ]]; then
  (cd SampleConsumer && timeout 300 dotnet run --project ../Bootstrap/Bootstrap.csproj --properties kcl.properties --execute 2>&1 | tee ../kcl_output.log) || [ $? -eq 124 ]
elif [[ "$RUNNER_OS" == "Windows" ]]; then
  (cd SampleConsumer && timeout 360 dotnet run --project ../Bootstrap/Bootstrap.csproj --properties kcl.properties --execute 2>&1 | tee ../kcl_output.log) || [ $? -eq 124 ]
else
  echo "Unknown OS: $RUNNER_OS"
  exit 1
fi

echo "---------ERROR LOGS HERE-------"
grep -i error kcl_output.log || echo "No errors found in logs"