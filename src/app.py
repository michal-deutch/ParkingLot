import boto3
from flask import Flask, request, jsonify

import parking_lot

app = Flask(__name__)
dynamodb = boto3.resource('dynamodb', 'us-east-1')

TABLE_NAME = 'ParkingLot'
CHARGE_INTERVAL_MIN = 15
CHARGE_COST = 2.5

table = dynamodb.Table(TABLE_NAME)


@app.route('/health', methods=['GET'])
def health():
    return "Parking Lot Manager"


@app.route('/entry', methods=['POST'])
def parking_entry():
    if 'plate' not in request.args or 'parkingLot' not in request.args:
        return jsonify({'errorMessage': 'provide plate and parkingLot'}), 400
    result = parking_lot.parking_entry(request.args.get('plate'), request.args.get('parkingLot'))
    if 'error' in result:
        return jsonify(result), 400
    return jsonify({'ticketId': result['ticketId']})


@app.route('/exit', methods=['POST'])
def parking_exit():
    if 'ticketId' not in request.args:
        return jsonify({'errorMessage': 'provide ticketId'})
    result = parking_lot.parking_exit(request.args.get('ticketId'))
    if 'error' in result:
        return jsonify(result), 400
    return jsonify(result)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
