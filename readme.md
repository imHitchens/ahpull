## AHPULL - Pull all auctions from all Classic WoW Auction Houses

### Runs automatically, given client_id and client_secret as env variables, and a path mapped to /data

Ex.
docker run -dt --name=ahpull \
-v /your/local/data/dir:/data \
-e client_id='foo' \
-e client_secret='bar' \
--name ahpull ahpull
