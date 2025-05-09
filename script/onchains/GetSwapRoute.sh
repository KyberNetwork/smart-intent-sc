#!/bin/bash

# Configuration
BASE_URL="https://aggregator-api.kyberswap.com"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --chain)
      CHAIN="$2"
      shift 2
      ;;
    --token-in)
      TOKEN_IN="$2"
      shift 2
      ;;
    --token-out)
      TOKEN_OUT="$2"
      shift 2
      ;;
    --amount-in)
      AMOUNT_IN="$2"
      shift 2
      ;;
    --sender)
      SENDER="$2"
      shift 2
      ;;
    --recipient)
      RECIPIENT="$2"
      shift 2
      ;;
    --slippage)
      SLIPPAGE="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Get Route Summary
ROUTE_RESPONSE=$(curl -s -L \
    -H "x-client-id:" \
    --url "${BASE_URL}/${CHAIN}/api/v1/routes?\
tokenIn=${TOKEN_IN}&\
tokenOut=${TOKEN_OUT}&\
amountIn=${AMOUNT_IN}&\
gasInclude=0")
ROUTE_SUMMARY=$(echo $ROUTE_RESPONSE | jq -r '.data.routeSummary')
# Get Encoded Data
ENCODED_RESPONSE=$(curl -s -L \
    --url "${BASE_URL}/${CHAIN}/api/v1/route/build" \
    --header "Content-Type: application/json" \
    -H "x-client-id: MyDApp" \
    --data @- << EOF
{
    "routeSummary": $ROUTE_SUMMARY,
    "sender": "$SENDER",
    "recipient": "$RECIPIENT",
    "slippageTolerance": $SLIPPAGE,
    "enableGasEstimation": false
}
EOF
)

# Extract and display results
CALL_DATA=$(echo $ENCODED_RESPONSE | jq -r '.data.data')
ROUTER_ADDRESS=$(echo $ENCODED_RESPONSE | jq -r '.data.routerAddress')
VALUE=$(echo $ENCODED_RESPONSE | jq -r '.data.transactionValue')

# Return the values in a structured JSON format
echo "{"
echo "  \"callData\": \"$CALL_DATA\","
echo "  \"routerAddress\": \"$ROUTER_ADDRESS\","
echo "  \"value\": \"$VALUE\""
echo "}"
