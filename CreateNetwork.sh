#!/bin/bash

#Author: Douglas Dias

GenerateGenesisFiles() {
    NODES=$1
    
    # Determines the quorum needed for votes on the protocol parameter updates
    QUORUM=$(((NODES/2)+1))

    echo Creating Genesis Files
    cardano-cli shelley genesis create --testnet-magic 42 --genesis-dir network/ --supply 12000000
    sed -i "/updateQuorum/c\ \"updateQuorum\": $(($QUORUM))," network/genesis.json
    sed -i "/updateQuorum/c\ \"updateQuorum\": $(($QUORUM))," network/genesis.spec.json
    echo -e "Genesis Files Created\n\n"
}

# Removing older network and logs folders, if they exists
rm -rf network
rm -rf logs

NODES=1

if [ $# -eq 0 ] || [ $1 -eq 1 ]; then
    echo One node will be created.
else
    echo $1 nodes will be created.
    NODES=$1
fi

# Step 1: Creating Genesis Files
GenerateGenesisFiles $NODES

# Step 2: Creating Genesis Keys
echo Creating Genesis Keys

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli shelley genesis key-gen-genesis --verification-key-file network/genesis-keys/genesis"$i".vkey --signing-key-file network/genesis-keys/genesis"$i".skey
done
echo -e "Genesis Keys Created\n\n"

# Step 3: Creating Genesis Delegate Keys
echo Creating Genesis Delegate Keys

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli shelley genesis key-gen-delegate --verification-key-file network/delegate-keys/delegate"$i".vkey --signing-key-file network/delegate-keys/delegate"$i".skey --operational-certificate-issue-counter network/delegate-keys/delegate-opcert"$i".counter
done
echo -e "Genesis Delegate Keys Createdn\n"

# Step 4: Creating Initial UTxO (Unspent Transaction Output, a ledger model)
echo Creating Initial UTxO

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli shelley genesis key-gen-utxo --verification-key-file network/utxo-keys/utxo"$i".vkey --signing-key-file network/utxo-keys/utxo"$i".skey
done
echo -e "Initial UTxO Created\n\n"

# Step 5: Creating VRF keys to prove that the node has the right to create a block in a slot
echo Creating VRF keys

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli shelley node key-gen-VRF --verification-key-file network/delegate-keys/delegate"$i".vrf.vkey --signing-key-file network/delegate-keys/delegate"$i".vrf.skey
done
echo -e "VRF Keys Created \n\n"

#Step 6: Creating Genesis Files Again
GenerateGenesisFiles $NODES

#Step 7: Creating KES Keys
echo Creating KES keys

for ((i = 1; i <= $NODES; i++)); do
    mkdir network/node"$i"
    cardano-cli shelley node key-gen-KES --verification-key-file network/node"$i"/kes.vkey --signing-key-file network/node"$i"/kes.skey
done
echo -e "KES Keys Created \n\n"

#Step 8: Issuing Operational Certificate
echo Issuing Operational Certificate

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli shelley node issue-op-cert --kes-verification-key-file network/node"$i"/kes.vkey --cold-signing-key-file network/delegate-keys/delegate"$i".skey --operational-certificate-issue-counter network/delegate-keys/delegate-opcert"$i".counter --kes-period 0 --out-file network/node"$i"/cert
done
echo -e "Operational Certificates Issued \n\n"

# Step 9: Creating Payment Keys
echo Creating Payment Keys

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli address key-gen --verification-key-file network/node"$i"/payment.vkey --signing-key-file network/node"$i"/payment.skey
done
echo -e "Payment Keys Created \n\n"

# Step 10: Creating Wallet Addresses
echo Creating Wallet Addresses

for ((i = 1; i <= $NODES; i++)); do
    cardano-cli address build --payment-verification-key-file network/node"$i"/payment.vkey --out-file network/node"$i"/payment.addr --testnet-magic 42
done
echo -e "Wallet Addresses Created\n\n"

# Step 11: Copy and edit configuration file, shared with all nodes
echo Copying the configuration file
cp utils/byron-mainnet/configuration.yaml network/
sed -i 's/^Protocol: RealPBFT/Protocol: TPraos/' network/configuration.yaml
sed -i 's/^minSeverity: Info/minSeverity: Debug/' network/configuration.yaml
sed -i 's/^TraceBlockchainTime: False/TraceBlockchainTime: True/' network/configuration.yaml
echo -e "Configuration file copied and edited \n\n"

#Step 12: Creating topology files
for ((i = 1; i <= $NODES; i++)); do
    touch network/node$i/topology.json

    FILE="network/node$i/topology.json"

    printf "{\n" >$FILE
    printf "\t\"Producers\": [ \n" >>$FILE

    for ((j = 1; j <= $NODES; j++)); do
        if [ $i != $j ]; then
            printf "\t\t{\n" >>$FILE
            printf "\t\t\t\"addr\": \"127.0.0.1\",\n" >>$FILE
            printf "\t\t\t\"port\": 30%0*d,\n" 2 $j >>$FILE
            printf "\t\t\t\"valency\": 1\n" >>$FILE

            NEXT=$(( j+1 ))

            if [ "$NEXT" != "$i" ]; then
                if [ "$NEXT" -le "$NODES" ]; then
                    printf "\t\t},\n" >>$FILE
                else 
                    printf "\t\t}\n" >>$FILE
                fi
            else
                if [ "$NEXT" -le "$NODES" ]; then
                    if [ "$i" == "$NODES" ]; then
                        printf "\t\t}\n" >>$FILE
                    else 
                        printf "\t\t},\n" >>$FILE
                    fi
                else 
                    printf "\t\t}\n" >>$FILE
                fi
            fi
        fi
    done

    printf "\t]\n" >>$FILE
    printf "}" >>$FILE
done
echo -e "Topology files created \n\n"

# Step 13: Creating Genesis Files Again
GenerateGenesisFiles $NODES

#Step 14: Starting the Nodes
echo Starting the Nodes

for ((i = 1; i <= $NODES; i++)); do
    PORT=$(printf "30%0*d" 2 $i)
    echo STARTING NODE"$i" AT PORT "$PORT"
    gnome-terminal -- cardano-node run --config network/configuration.yaml --topology network/node"$i"/topology.json --database-path network/node"$i"/db --socket-path network/node"$i"/node.sock --shelley-kes-key network/node"$i"/kes.skey --shelley-vrf-key network/delegate-keys/delegate"$i".vrf.skey --shelley-operational-certificate network/node"$i"/cert --port "$PORT"
done
echo -e "Nodes Started \n\n"

# Sleep for some time, so the nodes synchronize
sleep 30

# Step 15: Create metadata file
echo Create metadata file

mkdir network/metadata
touch network/metadata/metadata.json
METADATA_FILE="network/metadata/metadata.json"
printf "{\n\t\"1337\": {\n\t\t\"name\": \"hello world\",\n\t\t\"completed\": 0\n\t}\n}" >>$METADATA_FILE

printf "Metadata File Created \n\n"

# Step 16: Query UTXO
CARDANO_NODE_SOCKET_PATH=network/node1/node.sock cardano-cli query utxo --testnet-magic 42 --address $(cat network/node1/payment.addr) --cardano-mode