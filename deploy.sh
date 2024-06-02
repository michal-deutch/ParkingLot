# debug
# set -o xtrace
APP_PORT=5001

# Generate a unique key pair name and PEM file
KEY_NAME="cloud-course-$(date)"
KEY_PEM="$KEY_NAME.pem"

# Create the key pair and save it locally
echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name "$KEY_NAME" \
    | jq -r ".KeyMaterial" > "$KEY_PEM"

# Secure the key pair
chmod 400 "$KEY_PEM"

# Create a unique security group name
SEC_GRP="my-sg-$(date)"

# Create the security group
echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name "$SEC_GRP"       \
    --description "Access my instances"

# Retrieve the public IP of the local machine
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

# Allow SSH access to the local machine only
echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name "$SEC_GRP" --port 22 --protocol tcp \
    --cidr "$MY_IP"/32

# Allow HTTP access to the local machine only
echo "setup rule allowing HTTP (port $APP_PORT) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name "$SEC_GRP" --port $APP_PORT --protocol tcp \
    --cidr "$MY_IP"/32

# Specify the AMI ID for Ubuntu 20.04
UBUNTU_20_04_AMI="ami-042e8287309f5df03"

# Launch a new EC2 instance
echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

# Extract the instance ID
INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

# Wait for the instance to be running
echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Retrieve the public IP of the new instance
PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

# Output the instance ID and public IP
echo "New instance $INSTANCE_ID @ $PUBLIC_IP"

echo "create DynamoDB table"
TABLE_DEF=$(aws dynamodb create-table \
    --table-name ParkingLot \
    --attribute-definitions \
        AttributeName=ticket_id,AttributeType=S \
        AttributeName=plate,AttributeType=S \
        AttributeName=parking_lot,AttributeType=S \
    --key-schema \
        AttributeName=ticket_id,KeyType=HASH \
    --global-secondary-indexes \
        'IndexName=PlateParkingLotIndex,
        KeySchema=[{AttributeName=plate,KeyType=HASH},{AttributeName=parking_lot,KeyType=RANGE}],
        Projection={ProjectionType=ALL},
        ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
    --provisioned-throughput \
        ReadCapacityUnits=5,WriteCapacityUnits=5)

# Create roles
LAMBDA_ROLE_ARN=$(
  aws iam create-role \
  --role-name lambda_dynamodb_role \
  --assume-role-policy-document file://trust-policy.json | jq -r '.Role' | jq -r '.Arn')

PUT_POLICY=$(aws iam put-role-policy \
  --role-name lambda_dynamodb_role \
  --policy-name DynamoDBFullAccessPolicy \
  --policy-document file://policy.json)

# Wait for policy to update
sleep 5

# Upload the ZIP file to AWS Lambda
echo "Uploading Flask application to AWS Lambda..."

LAMBDA_ENTRY_ARN=$(aws lambda create-function \
    --function-name parking_lot_entry \
    --runtime python3.8 \
    --handler lambda_handler.entry_handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file fileb://lambda_function.zip | jq -r '.FunctionArn')

LAMBDA_EXIT_ARN=$(aws lambda create-function \
    --function-name parking_lot_exit \
    --runtime python3.8 \
    --handler lambda_handler.exit_handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file fileb://lambda_function.zip | jq -r '.FunctionArn')

# Create logs group
aws logs create-log-group --log-group-name /aws/lambda/parking_lot_entry
aws logs create-log-group --log-group-name /aws/lambda/parking_lot_exit

# Create IAM role for APIGateway
API_GW_ROLE_ARN=$(
  aws iam create-role \
  --role-name api_gw_role \
  --assume-role-policy-document file://trust-policy.json | jq -r '.Role' | jq -r '.Arn')
aws iam put-role-policy --role-name api_gw_role --policy-name InvokeLambdaPolicy --policy-document file://gw_policy.json

sleep 5


# Create an API Gateway endpoint to trigger the Lambda function
API_ID=$(aws apigatewayv2 create-api \
    --name parking_lot_gw \
    --protocol-type HTTP | jq -r '.ApiId')

# Create the Lambda integration
ENTRY_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-method POST \
    --integration-uri "$LAMBDA_ENTRY_ARN" \
    --payload-format-version '2.0' | jq -r '.IntegrationId')

EXIT_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-method POST \
    --integration-uri "$LAMBDA_EXIT_ARN" \
    --payload-format-version '2.0' | jq -r '.IntegrationId')

# Create routings
aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "POST /exit" \
    --target integrations/"$EXIT_INTEGRATION_ID"

aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "POST /entry" \
    --target integrations/"$ENTRY_INTEGRATION_ID"

aws apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name 'prod' \
    --auto-deploy

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws lambda add-permission \
   --statement-id api-gw-exit-statement \
   --action lambda:InvokeFunction \
   --function-name "$LAMBDA_EXIT_ARN" \
   --principal apigateway.amazonaws.com \
   --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/exit"

aws lambda add-permission \
   --statement-id api-gw-exit-statement \
   --action lambda:InvokeFunction \
   --function-name "$LAMBDA_ENTRY_ARN" \
   --principal apigateway.amazonaws.com \
   --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/entry"

# Deploy the application to the instance
echo "deploying code.."
scp -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" src/app.py src/parking_lot.py requirements.txt ~/.aws/credentials ubuntu@"$PUBLIC_IP":/home/ubuntu/
aws apigatewayv2 create-deployment --api-id "$API_ID" --stage-name prod

# Set up the production environment and run the Flask app
echo "setup production environment"
# shellcheck disable=SC2086
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    sudo apt install python3-pip -y
    pip3 install -r /home/ubuntu/requirements.txt
    # run app
    nohup flask run --host 0.0.0.0 --port 5001 &>/dev/null &
    exit
EOF

# Get the URL of the deployed API Gateway endpoint
SERVERLESS_ENDPOINT=$(aws apigatewayv2 get-api --api-id="$API_ID" | jq -r '.ApiEndpoint')

echo "=========== Finished ==========="
echo "- Serverless Endpoint: $SERVERLESS_ENDPOINT/prod"
echo "- EC2 Endpoint:        http://$PUBLIC_IP:5001"
