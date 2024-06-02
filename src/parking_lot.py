import os

import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime
import uuid

region = os.getenv('AWS_REGION')
if region:
    dynamodb = boto3.resource('dynamodb', region)
else:
    dynamodb = boto3.resource('dynamodb')

cache = {}
TABLE_NAME = 'ParkingLot'
CHARGE_INTERVAL_MIN = 15
CHARGE_COST = 2.5

table = dynamodb.Table(TABLE_NAME)

def parking_entry(plate, parking_lot):
    # Query to check if the car is already parked in the specified parking lot
    try:
        response = table.query(
            IndexName='PlateParkingLotIndex',
            KeyConditionExpression=Key('plate').eq(plate) & Key('parkingLot').eq(parking_lot)
        )
    except Exception:
        response = {'Items': None}
    if response['Items']:
        return {'error': 'This car is already parked in the specified parking lot.'}

    ticket_id = str(uuid.uuid4())
    entry_time = datetime.now()

    ticket_record = {
        'ticketId': ticket_id,
        'plate': plate,
        'parkingLot': parking_lot,
        'entryTime': int(datetime.timestamp(entry_time))
    }

    try:
        table.put_item(Item=ticket_record)
    except Exception:
        cache[ticket_record['ticketId']] = ticket_record

    return ticket_record


def _get_charge(entry_time, exit_time):
    parked_time = exit_time - entry_time
    parked_minutes = parked_time.total_seconds() / 60
    intervals = (parked_minutes // CHARGE_INTERVAL_MIN) + (1 if parked_minutes % CHARGE_INTERVAL_MIN else 0)
    return parked_time, intervals * CHARGE_COST


def parking_exit(ticket_id):
    exit_time = datetime.now()
    if not ticket_id:
        return {'error': 'Missing ticketId.'}
    try:
        response = table.get_item(Key={'ticketId': ticket_id})
        if 'Item' not in response:
            return {'error': 'Your ticket is invalid, please send the right one.'}
        record = response['Item']
    except Exception:
        record = cache.get(ticket_id)

    entry_time = datetime.fromtimestamp(record['entryTime'], tz=None)
    parked_time, charge = _get_charge(entry_time, exit_time)

    try:
        table.delete_item(Key={'ticketId': ticket_id})
    except Exception:
        cache.pop(ticket_id)

    return {
        'plate': record['plate'],
        'parkingLot': record['parkingLot'],
        'totalParkedTime': str(parked_time),
        'charge': round(charge, 2)
    }

