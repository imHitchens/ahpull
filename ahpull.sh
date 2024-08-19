#!bin/bash
curl -u $client_id:$client_secret -d grant_type=client_credentials https://oauth.battle.net/token | jq -r '.access_token' | 
while read access_token;
do 
    cat namespaces.json | jq -r '.[].regions.[]' |
    while read region;
    do 
        cat namespaces.json | jq -r '.[].namespaces.[].dynamic' |
        while read namespace;
        do
            curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/index?namespace=$namespace$region" |
            jq -r '.connected_realms[].href' |
            while read connectedRealmId;
            do
                connectedRealmId=${connectedRealmId##*/}
                connectedRealmId=${connectedRealmId%\?*}
                curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions/index?namespace=$namespace$region&locale=$locale&access_token=$access_token" | 
                jq '.auctions[]' | jq '.id' | 
                while read ahid;
                do
                    mkdir -p data/tmp
                    mkdir -p mkdir -p data/auctions
                    write_date=$(date +%s)
                    curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions/$ahid?namespace=$namespace$region&$locale&$access_token" | 
                    jq ".auctions[]" | 
                    jq "{ region: \"$namespace$region\", connectedRealmId: $connectedRealmId, ahid: $ahid, id: .id, time: $write_date, itemid: .item.id, itemrand: .item.rand, itemseed: .item.seed, time_left: .time_left, bid: .bid, buyout: .buyout, quantity: .quantity }" | 
                    jq -r "join(\";\")" >> data/tmp/$namespace$region$connectedRealmId_$time.csv
                    mv data/tmp/$namespace$region$connectedRealmId_$time.csv data/auctions/$namespace$region$connectedRealmId_$time.csv ;
                done;
            done;
        done;
    done;
done