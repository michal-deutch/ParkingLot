import json

from parking_lot import parking_entry, parking_exit


def entry_handler(event, context):
    if 'queryStringParameters' not in event:
        return {
            'statusCode': 400,
            'body': json.dumps({'errorMessage': "provide plate and parkingLot as params"})
        }
    params = event['queryStringParameters']
    if 'plate' not in params or 'parkingLot' not in params:
        return {
            'statusCode': 400,
            'body': json.dumps({'errorMessage': "provide plate and parkingLot as params"})
        }

    result = parking_entry(params['plate'], params['parkingLot'])

    if 'error' in result:
        return {
            'statusCode': 400,
            'body': json.dumps(result)
        }
    return {
        'statusCode': 200,
        'body': json.dumps({'ticketId': result['ticketId']})
    }


def exit_handler(event, context):
    if 'queryStringParameters' not in event:
        return {
            'statusCode': 400,
            'body': json.dumps({'errorMessage': "provide ticketId"})
        }
    if 'ticketId' not in event['queryStringParameters']:
        return {
            'statusCode': 400,
            'body': json.dumps({'errorMessage': "provide ticketId"})
        }
    result = parking_exit(event['queryStringParameters']['ticketId'])

    code = 200
    if 'error' in result:
        code = 400
    return {
        'statusCode': code,
        'body': json.dumps(result)
    }