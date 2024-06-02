# Parking Lot Manager

#### Michal Deutch (206094989), Shaked Ahronoviz (305325037)

A Python server to manage a parking lot with two HTTP endpoints:
1. **POST /entry?plate=123-123-123&parkingLot=382**
2. **POST /exit?ticketId=1234**
3. **Available Endpoints**
   1. Serverless: 
   2. EC2:


## Deployment

- Download AWS cli and run `aws config`
- `source deploy.sh`
- The relevant endpoint show at the end of the script

````
=========== Finished ===========
- Serverless Endpoint: https://jsjinm8po2.execute-api.us-east-1.amazonaws.com/prod
- EC2 Endpoint:        http://54.242.60.103:5001
````

## Testing

```
pip install pytest
pytest test_parking_lot_manager.py
```
