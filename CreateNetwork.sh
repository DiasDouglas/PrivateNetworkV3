#!/bin/bash

#Author: Douglas Dias

GenerateGenesisFiles(){
    echo Creating Genesis Files 
    cardano-cli shelley genesis create --testnet-magic 42 --genesis-dir network/ --supply 12000000
    sed -i 's/^"updateQuorum": 5/"updateQuorum": 12/' network/genesis.json
    sed -i 's/^"updateQuorum": 5/"updateQuorum": 12/' network/genesis.spec.json
    echo -e "Genesis Files Created\n\n"
}

NODES=1

if [ $# -eq 0 ] || [ $1 -eq 1 ]
    then
        echo One node will be created.
    else
        echo $1 nodes will be created.
        NODES=$1
fi

# Step 1: Creating Genesis Files
GenerateGenesisFiles

# Step 2: Creating Genesis Keys
echo Creating Genesis Keys

for (( i=1;i<=$NODES;i++ )) 
do
    cardano-cli shelley genesis key-gen-genesis --verification-key-file network/genesis-keys/genesis"$i".vkey --signing-key-file network/genesis-keys/genesis"$i".skey
done
echo -e "Genesis Keys Created\n\n"

# Step 3: Creating Genesis Delegate Keys
echo Creating Genesis Delegate Keys

for (( i=1;i<=$NODES;i++ )) 
do
    cardano-cli shelley genesis key-gen-delegate --verification-key-file network/delegate-keys/delegate"$i".vkey --signing-key-file network/delegate-keys/delegate"$i".skey --operational-certificate-issue-counter network/delegate-keys/delegate-opcert"$i".counter
done
echo -e "Genesis Delegate Keys Createdn\n"

# Step 4: Creating Initial UTxO (Unspent Transaction Output, a ledger model)
echo Creating Initial UTxO

for (( i=1;i<=$NODES;i++ )) 
do
    cardano-cli shelley genesis key-gen-utxo --verification-key-file network/utxo-keys/utxo"$i".vkey --signing-key-file network/utxo-keys/utxo"$i".skey
done
echo -e "Initial UTxO Created\n\n"

# Step 5: Creating VRF keys to prove that the node has the right to create a block in a slot
echo Creating VRF keys

for (( i=1;i<=$NODES;i++ )) 
do
    cardano-cli shelley node key-gen-VRF --verification-key-file network/delegate-keys/delegate"$i".vrf.vkey --signing-key-file network/delegate-keys/delegate"$i".vrf.skey
done
echo -e "VRF Keys Created \n\n"

#Step 6: Creating Genesis Files Again
GenerateGenesisFiles

#Step 7: Creating KES Keys
echo Creating KES keys

for (( i=1;i<=$NODES;i++ )) 
do
    mkdir network/node"$i"
    cardano-cli shelley node key-gen-KES --verification-key-file network/node"$i"/kes.vkey --signing-key-file network/node"$i"/kes.skey
done
echo -e "KES Keys Created \n\n"

#Step 8: Issuing Operational Certificate
echo Issuing Operational Certificate

for (( i=1;i<=$NODES;i++ )) 
do
    cardano-cli shelley node issue-op-cert --kes-verification-key-file network/node"$i"/kes.vkey --cold-signing-key-file network/delegate-keys/delegate"$i".skey --operational-certificate-issue-counter network/delegate-keys/delegate-opcert"$i".counter --kes-period 0 --out-file network/node"$i"/cert
done
echo -e "Operational Certificates Issued \n\n"

# Step 9: Copy and edit configuration file, shared with all nodes
echo Copying the configuration file
cp utils/byron-mainnet/configuration.yaml network/
sed -i 's/^Protocol: RealPBFT/Protocol: TPraos/' network/configuration.yaml
sed -i 's/^minSeverity: Info/minSeverity: Debug/' network/configuration.yaml
sed -i 's/^TraceBlockchainTime: False/TraceBlockchainTime: True/' network/configuration.yaml
echo -e "Configuration file copied and edited \n\n"

#Step 10: Creating topology files
for (( i=1;i<=$NODES;i++ )) 
do
    touch network/node$i/topology.json

    FILE="network/node$i/topology.json"

    printf "{\n" > $FILE
    printf "\t\"Producers\": [ \n" >> $FILE

    for (( j=1;j<=$NODES;j++ ))
    do
        if [ $i != $j ]
        then
            printf "\t\t{\n" >> $FILE
            printf "\t\t\t\"addr\": \"127.0.0.1\",\n" >> $FILE
            printf "\t\t\t\"port\": 30%0*d,\n" 2 $j >> $FILE
            printf "\t\t\t\"valency\": 1\n" >> $FILE

            if [ "$j" -lt "$NODES" ]
            then
                printf "\t\t},\n" >> $FILE
            else
                printf "\t\t}\n" >> $FILE
            fi
        fi
    done

    printf "\t]\n" >> $FILE
    printf "}" >> $FILE
done
echo -e "Topology files created \n\n"

#Step 11: Creating Genesis Files Again
GenerateGenesisFiles

#Step 12: Starting the Nodes
echo Starting the Nodes

for (( i=1;i<=$NODES;i++ )) 
do
    PORT=$(printf "30%0*d" 2 $i)
    
    gnome-terminal -- cardano-node run --config network/configuration.yaml --topology network/node"$i"/topology.json --database-path network/node"$i"/db --socket-path network/node"$i"/node.sock --shelley-kes-key network/node"$i"/kes.skey --shelley-vrf-key network/delegate-keys/delegate"$i".vrf.skey --shelley-operational-certificate network/node"$i"/cert --port "$PORT"
done
echo -e "Nodes Started \n\n"
