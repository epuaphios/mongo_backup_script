SERVICE_NAME="$1"
MONGO_HOST=127.0.0.1
MONGO_PORT=0
mail_adres=
BACKUP_DIR=/mnt/backupnfs

if [ "$SERVICE_NAME" = "mongodb1" ]; then
  MONGO_PORT=27017
elif [ "$SERVICE_NAME" = "mongodb2" ]; then
  MONGO_PORT=27018 

  MONGO_PORT=27030
else
  echo "Servis Bulunamadi..."
  echo "$SERVICE_NAME Servis Bulunamadi..." | mail -s "Mongo DB Backup Hata!!! - $SERVICE_NAME" $mail_adres
  exit
fi
echo "MONGO_PORT=$MONGO_PORT"

function select_secondary_member {

# Return list of with all replica set members
members=( $(mongo --quiet --host $MONGO_HOST:$MONGO_PORT --eval 'rs.conf().members.forEach(function(x){ print(x.host) })') )

# Check each replset member to see if it's a secondary and return it.

if [ ${#members[@]} -gt 1 ]; then
for member in "${members[@]}"; do

is_secondary=$(mongo --quiet --host $member --eval 'rs.isMaster().secondary')
case "$is_secondary" in
'true') # First secondary wins ...
secondary=$member
break
;;
'false') # Skip particular member if it is a Primary.
continue
;;
*) # Skip irrelevant entries. Should not be any anyway ...
continue
;;
esac
done
fi
}


select_secondary_member secondary
echo "#################################################################"
echo "using secondary  " $secondary "replica set for  backup"
echo "#################################################################"


if [ -n "$secondary" ]; then
  DBHOST=${secondary%%:*}
  DBPORT=${secondary##*:}
else
  SECONDARY_WARNING="WARNING: No suitable Secondary found in the Replica Sets. Falling back to ${DBHOST}."
  echo "Backup alinabilecek SECONDARY bulunamadi." | mail -s "Mongo DB Backup Hata!!! - $SERVICE_NAME" $mail_adres
  exit;
fi



## Lock islemi
echo "Mongo Database Lock Edilir."
LOCK_RESULT=`mongo --host $DBHOST --port $DBPORT  --quiet  --eval "printjson(db.fsyncLock().ok)"` 
if [ "$LOCK_RESULT" = "1" ]; then
  echo "LOCK ISLEMI BASARILI"
else  
  echo "LOCK ISLEMI BASARISIZ"
  echo "LOCK ISLEMI BASARISIZ" | mail -s "Mongo DB Backup Hata!!! - $SERVICE_NAME" $mail_adres
  exit;
fi  

## Gecmis Backuplar Silinecek
if [ `date +%H` = "01" ]; then
  echo "01'da alinan backuplar 10 gun saklanacagi icin silinmez."
else  
  echo "24 saat once alinan backup silinecek"
  echo `date --date='1 day ago'  +%Y-%m-%d`/`date +%H-*`
  rm -rf $BACKUP_DIR/backup_data/$SERVICE_NAME/`date --date='1 day ago'  +%Y-%m-%d`/`date +%H-*`
  echo "10 gun oncesine ait backuplar temizlenir."
  echo `date --date='10 day ago'  +%Y-%m-%d`
  rm -rf $BACKUP_DIR/backup_data/$SERVICE_NAME/`date --date='10 day ago'  +%Y-%m-%d`
fi  

## Backup
echo "Mongo Database Backup alinir."
mongodump --host $DBHOST --port $DBPORT --oplog --out $BACKUP_DIR/backup_data/$SERVICE_NAME/`date +%Y-%m-%d`/`date +%H-%M`

RC=$?
if [ $RC -ne "0" ]; then
  echo "Mongo Database Backup HATA."
  echo "Mongo Database Backup BASARISIZ!!!" | mail -s "Mongo DB Backup Hata!!! - $SERVICE_NAME" $mail_adres
  exit;
else
  echo "Mongo Database Backup BASARILI."
fi


## Unlock islemi
echo "Mongo Database Lock Edilir."
for i in {1..9}  ;do 
  LOCK_RESULT=`mongo --host $DBHOST --port $DBPORT  --quiet  --eval "printjson(db.fsyncUnlock().ok)"`
  if [ "$LOCK_RESULT" = "1" ]; then
    echo "UNLOCK ISLEMI BASARILI"
  elif [ "$LOCK_RESULT" = "0" ]; then
    ERROR_MSG=`mongo --host $DBHOST --port $DBPORT  --quiet  --eval "printjson(db.fsyncUnlock().errmsg)"`
    if [ "$ERROR_MSG" = "fsyncUnlock called when not locked" ]; then 
      break;
    fi
  else  
    echo "UNLOCK ISLEMI BASARISIZ"
	echo "UNLOCK ISLEMI BASARISIZ" | mail -s "Mongo DB Backup Hata!!! - $SERVICE_NAME" $mail_adres
	exit;
  fi  
done

