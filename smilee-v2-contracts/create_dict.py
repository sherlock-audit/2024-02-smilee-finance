# Python program to read
# json file


import json
import sys

scripts = {
    "01_CoreFoundations.s.sol": ["run"],
    "02_Token.s.sol": ["deployToken"],
    "03_Factory.s.sol": ["createIGMarket"]
}

contracts = {}

chainid = 31337
if len(sys.argv) <= 1:
    print("Missing chain id parameter, using 31337")
else:
    chainid = sys.argv[1]

for k in scripts.keys():
    for fun in scripts[k]:
        f = open(f"broadcast/{k}/{chainid}/{fun}-latest.json")
        data = json.load(f)

        create_ct_txs = [tx for tx in data["transactions"] if tx["transactionType"] == "CREATE"]
        for tx in create_ct_txs:
            contract_name = tx['arguments'][1] if tx['contractName'] == "TestnetToken" else tx['contractName']
            contracts[contract_name] = tx['contractAddress']

        # Closing file
        f.close()


with open("out/addresses.json", "w") as outfile:
    json.dump(contracts, outfile, indent=4)
