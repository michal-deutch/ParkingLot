# test_parking_lot_manager.py
import pytest
import requests
import time
BASE_URL="http://127.0.0.1:5001"
# BASE_URL = 'http://54.242.60.103:5001'
# BASE_URL="https://jsjinm8po2.execute-api.us-east-1.amazonaws.com/prod"

@pytest.fixture
def entry_data():
    return {
        'plate': '123-123-123',
        'parkingLot': '382'
    }


def test_parking_lot(entry_data):
    response = requests.post(f"{BASE_URL}/entry", params=entry_data)
    assert response.status_code == 200
    data = response.json()
    assert 'ticketId' in data
    ticket_id = 'a5128db5-a8cc-421b-b87c-dadc8aeb7450'#data['ticketId']
    time.sleep(1)

    # try once more on the same car and parking lot
    response = requests.post(f"{BASE_URL}/entry", params=entry_data)
    assert response.status_code == 400

    time.sleep(1)
    response = requests.post(f"{BASE_URL}/exit", params={'ticketId': ticket_id})
    assert response.status_code == 200
    data = response.json()

    assert 'plate' in data and data['plate'] == entry_data['plate']
    assert 'parkingLot' in data and data['parkingLot'] == entry_data['parkingLot']
    assert 'charge' in data and round(data['charge'], 2) == round(2.5, 2)

