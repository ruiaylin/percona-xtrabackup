############################################################################
# Test basic local backup with compression and encryption
############################################################################

require_qpress

encrypt_algo="AES256"
encrypt_key="percona_xtrabackup_is_awesome___"

innobackupex_options="--compress --compress-threads=4 --compress-chunk-size=8K --encrypt=$encrypt_algo --encrypt-key=$encrypt_key --encrypt-threads=4 --encrypt-chunk-size=8K"

data_decrypt_cmd="for i in *.xbcrypt; do \
xbcrypt -d -a $encrypt_algo -k $encrypt_key < \$i > \${i:0:\${#i}-8}; \
rm -f \$i; done; \
for i in ./sakila/*.xbcrypt; do \
xbcrypt -d -a $encrypt_algo -k $encrypt_key < \$i > \${i:0:\${#i}-8}; \
rm -f \$i; done;"

data_decompress_cmd="for i in *.qp;  do qpress -d \$i ./; done; \
for i in sakila/*.qp; do qpress -d \$i sakila/; done"

. inc/xb_local.sh
