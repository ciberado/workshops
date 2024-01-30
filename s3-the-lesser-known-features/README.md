# S3, 

the lesser known details


1. Improving ingestion performance
2. Why is pagination important?
3. S3 as a SQL database
4. Divide and conquer you files
5. Mountpoint: the good, the bad and the awful
6. Multipart upload




## Improving ingestion



Start a `tmux` session, configure you region, and create your own bucket:

```bash
tmux

export AWS_DEFAULT_REGION=us-east-1
export BUCKET_NAME=s3workshop$RANDOM
echo Your bucket name is going to be $BUCKET_NAME. Take note of it.
aws s3 mb s3://$BUCKET_NAME
```



Get the required data to test the upload performance and start a new pane
with `htop`:

```bash
wget https://github.com/ciberado/workshops/raw/main/s3-the-lesser-known-features/assets/covers.zip
mkdir data
unzip covers.zip  01*.jpg 02*.jpg -d covers/
cd covers
ls . | wc -l
```
```bash
tmux splitw -t "$session_uuid:" -d "htop"
```



Test how much time does it take to upload those files. Note that `s3 cp`
will launch a thread for each processor in the VM:

```bash
time aws s3 cp --recursive . s3://$BUCKET_NAME/covers-simple/ > /dev/null
```



Test now how does it takes if we divide all files in groups (using
the first three letters of the name as the prefix) and then
upload two files in parallel, trying to saturate the compute capacity:

```bash
time ls . \
  | cut -c1-3 \
  | uniq \
  | xargs -P 6 -I '{}' \
      sh -c 'aws s3 cp --recursive \
          --exclude "*" --include "{}*" \
          . s3://$BUCKET_NAME/covers-parallel/ > /dev/null' 
```



Optionally, you can close the additional pane:

```bash
tmux kill-pane -a -t "$session_uuid:"
```



## S3 queries



### The lack of Glob




S3 operations doesn't support typical Linux `*` for working with files: only
prefixes are directly implemented in the path argument. Additionally, object
keys are not hierarchical: the `/` is considered just like any other character.
But it influences the response provided by the AWS CLI, as you will see:

```bash
aws s3 ls s3://$BUCKET_NAME/covers-simple     # (ok, but not what you intended)
aws s3 ls s3://$BUCKET_NAME/covers-simple/    # (ok)
aws s3 ls s3://$BUCKET_NAME/covers-simple/01* # (what?)
aws s3 ls s3://$BUCKET_NAME/covers-simple/01  # (ok, surprisingly)
aws s3 ls s3://$BUCKET_NAME/covers-simple/01*.jpg # (double what?)
```



### How pagination works




Check how the most basic list query works: it returns a number of items (max 1000),
and a pagination token.

```bash
aws s3api list-objects-v2 \
  --bucket $BUCKET_NAME \
  --prefix covers-simple/ \
  --max-items 3
```



Save the token to be able to get the next bunch of files:

```bash
TOKEN=$(aws s3api list-objects-v2 \
  --bucket $BUCKET_NAME \
  --prefix covers-simple/ \
  --max-items 3 \
  | tee first-page.json \
  | jq .NextToken -r)
echo Next token is $TOKEN.
cat first-page.json
```



Use the saved token to continue with the process of getting all the
names:

```bash
token=$(aws s3api list-objects-v2 \
  --bucket $BUCKET_NAME \
  --prefix covers-simple/ \
  --max-items 3 \
  --starting-token $TOKEN \
  | tee second-page.json \
  | jq .NextToken -r)
  cat second-page.json
```



How do you think this can impact the management of big amounts
of files? To solve this problem, on approach consist in using 
[S3 Inventory](https://docs.aws.amazon.com/AmazonS3/latest/userguide/configure-inventory.html). It will generate a daily report with information regarding
all the files included in the selection criteria.




To further explore your data distribution, it is recommended to
take advantage of the [Storage Lense](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage_lens.html) service, that automatically aggregates information
and presents it using different dashboards.




## S3 as an almost free Database



Get the dataset that we will use for exploring [S3 Select](https://docs.aws.amazon.com/AmazonS3/latest/userguide/selecting-content-from-objects.html):

```bash
cd
wget https://github.com/ciberado/workshops/raw/main/s3-the-lesser-known-features/assets/book32-listing.csv
ls -lh # Around 38MB
cat book32-listing.csv | wc -l # Aprox. 200K lines
head book32-listing.csv # It is a CSV file
```



The file is codified using `ISO8859-1` instead of the supported `UTF-8`, so we
need to convert it:

```bash
file -i book32-listing.csv # Unknown codification
iconv -f latin1  -t UTF-8 book32-listing.csv > book32-listing-utf8.csv
file -i book32-listing-utf8.csv # Now it is UTF-8
```



We can move it to S3:

```bash
aws s3 cp book32-listing-utf8.csv s3://$BUCKET_NAME/
```



Now we can directly query the data (almost) for free! And the result will
be easily manipulated using javascript.

```bash
SQL='SELECT * FROM s3object LIMIT 10'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": {}, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq
```




Of course, it is possible to use projections. But aliases cannot be
included in the `where` clause:

```bash
SQL='SELECT _1 AS amazon_index, _2 AS filename, _3 AS image_url, 
            _4 AS title, _5 AS author,_6 AS category_id, _7 AS category 
     FROM s3object 
     LIMIT 3
'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": {}, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq
```



Many operations will require proper configuration of the serializers,
for example to ensure the process understand that the strings are quoted.
Next query will fail:

```bash
SQL='SELECT count(*) FROM s3object'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": {}, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" # Fail
```



But this one will work:

```bash
SQL='SELECT count(*) FROM s3object'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": { "AllowQuotedRecordDelimiter" : true }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq
```



It is **not possible** to use `GROUP BY`, but you can include
`WHERE` clauses in aggregations:

```bash
SQL='SELECT COUNT(*) AS amount 
     FROM s3object 
     WHERE _7 = '\''History'\'''
echo $SQL

aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": { "AllowQuotedRecordDelimiter" : true }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json
```



Other aggregation operations are available, like `MIN`, `MAX` or even `SUM`. But
casting is mandatory, as every field is considered a string by default:

```bash
SQL='SELECT MIN(CAST(_6 as INT)) AS minimum, 
            MAX(CAST(_6 AS INT)) AS maximum 
     FROM s3object
'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": { "AllowQuotedRecordDelimiter" : true }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json
```




*S3 Select* works fine with compressed data, that can save up to 80% of storage cost.
First, let's compress our file and upload the new version:

```bash
gzip -k book32-listing-utf8.csv
ls *.csv* -lh  # Aprox 30% of the original size
aws s3 cp book32-listing-utf8.csv.gz s3://$BUCKET_NAME/
```



Now it is possible to query that compressed file:

```bash
SQL='SELECT MIN(CAST(_6 as INT)) AS minimum, 
            MAX(CAST(_6 AS INT)) AS maximum 
     FROM s3object
'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.csv.gz \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"CSV": {"AllowQuotedRecordDelimiter" : true }, "CompressionType": "GZIP"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json
```



Columnar file formats may provide better performance. Let's get
a version of our file in [parquet](https://en.wikipedia.org/wiki/Apache_Parquet).

```bash
wget https://github.com/ciberado/workshops/raw/main/s3-the-lesser-known-features/assets/book32-listing-utf8.parquet
```



We can check the content of the file with the [parq](https://pypi.org/project/parquet-cli/) command. 
Apologies, as you will see how I duplicated some lines with the conversion:

```bash
parq book32-listing-utf8.parquet
parq book32-listing-utf8.parquet --head 10 # Columnar format!!
```



Upload the file to your bucket, so you can play with it:

```bash
aws s3 cp book32-listing-utf8.parquet s3://$BUCKET_NAME/
```



S3 Select is perfectly compatible with *parquet*, and now it understands
the type of each field and the associated name:

```bash
SQL='SELECT * FROM s3object LIMIT 3'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.parquet \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"Parquet": { }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq
```



An example with aggregated data:

```bash
SQL='SELECT MIN(category_id) AS minimum, 
     MAX(category_id) AS maximum 
     FROM s3object
'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.parquet \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"Parquet": { }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq
```



And a quite fast free text search (sorry for the duplications, my fault):

```bash
SQL='SELECT amazon_index, filename, image_url, 
            title, author, category_id, category 
    FROM s3object
    WHERE author like '\''%Javi%'\''
'
aws s3api select-object-content \
    --bucket $BUCKET_NAME \
    --key book32-listing-utf8.parquet \
    --expression "$SQL" \
    --expression-type 'SQL' \
    --input-serialization '{"Parquet": { }, "CompressionType": "NONE"}' \
    --output-serialization '{"JSON": {}}' "output.json" && \
cat output.json | jq '.amazon_index + " " + .title'
```




For large files, it can be very convenient to parallelize the searchs:

```bash
FILE_SIZE=$(stat -c %s book32-listing-utf8.parquet) && \
echo The file is $FILE_SIZE bytes long.

for ((i = 0 ; i < 4 ; i++ )) 
do 
  FIRST_BYTE=$(bc <<<  "scale = 10; $FILE_SIZE / 4 * $i")
  FIRST_BYTE=$(printf "%.*f\n" "0" "$FIRST_BYTE")
  LAST_BYTE=$(bc <<< "scale = 10; $FILE_SIZE / 4 * ($i+1) + 1")
  LAST_BYTE=$(printf "%.*f\n" "0" "$LAST_BYTE")
  echo "Job $i: from $FIRST_BYTE to $LAST_BYTE."

  SQL='SELECT amazon_index, filename, image_url, 
              title, author, category_id, category 
      FROM s3object
      WHERE author like '\''%Javi%'\''
  '
  aws s3api select-object-content \
      --scan-range "Start=$FIRST_BYTE,End=$LAST_BYTE" \
      --bucket $BUCKET_NAME \
      --key book32-listing-utf8.parquet \
      --expression "$SQL" \
      --expression-type 'SQL' \
      --input-serialization '{"Parquet": { }, "CompressionType": "NONE"}' \
      --output-serialization '{"JSON": {}}' "output-$i.json" \
      > /dev/null 2>&1 &
done
```



After the completion of all the jobs it is possible to get the results
easily. Select will include partial records in the answer, so be careful
processing potential duplicates.

```bash
cat output-*.json | sort | jq
```




## Range selections




How it was the last example possible? S3 in general supports range
retrieving: to check it, let's create now a file with known content:

```bash
for i in {0..999999}; do printf "%09d\n" $i >> numbers.txt ; done
cat numbers.txt | wc -l
ls -lh numbers.txt
head numbers.txt
tail numbers.txt
```




Your local operating system can extract information of the file,
given we know exactly how it is structured:

```bash
i=0
dd if=numbers.txt skip=$(( i * 10)) count=10 status=none iflag=skip_bytes,count_bytes; 
i=5000
dd if=numbers.txt skip=$(( i * 10)) count=10 status=none iflag=skip_bytes,count_bytes; 
```




Let's copy the new file to your S3 bucket, and then we will do the previous
trick but using the API, thanks to *range selections*:

```bash
aws s3 cp numbers.txt s3://$BUCKET_NAME/
i=5000
aws s3api get-object \
  --bucket $BUCKET_NAME \
  --key numbers.txt \
  --range bytes=$(( i * 10))-$(( i * 10 + 9 )) n.txt
cat n.txt
```



## Mountpoint: treating S3 as a filesystem




Since S3 became strongly consistent, it is more suitable to be mounted
as a filesystem. Amazon supports the [MountPoint](https://aws.amazon.com/s3/features/mountpoint/) project to do it... and it works surprisingly well.

```bash
mount-s3 --version
```




Let's create a directory to map our bucket in our local filesystem, and another
one to store cached metadata and objects:

```bash
mkdir .s3-cache
mkdir bucket
mount-s3 $BUCKET_NAME bucket --cache .s3-cache --allow-delete
```




Do you want to check the result? Be my guest:

```bash
ls bucket
```



You can even create new files, but as soon as the file descriptor is closed,
you will not be able to append to it anymore:

```bash
echo "Hola" > bucket/greetings.txt
cat bucket/greetings.txt
aws s3 ls s3://$BUCKET_NAME
echo "Adios" > bucket/greetings.txt # fail
```



But, you know what? It is aware of how to use *range selections*:

```bash
i=70000
dd if=bucket/numbers.txt skip=$(( i * 10)) count=10 status=none iflag=skip_bytes,count_bytes; 
```



And this can give use a very powerful tool if you combine it with a
compression format that supports position dictionaries. First, lets's
`zip` our old friend, the `~/covers/` directory. And no, it is not possible
to directly zip into the `bucket` folder.

```bash
sudo apt install zip -y
cd covers
zip ../covers.zip *.jpg
cd ..
ls -l covers.zip
```



The `unzip` command supports direct extraction of one file. For example:

```bash
RANDOM_FILE_NAME=$(ls covers/  |sort -R | tail -1)
echo We will play with $RANDOM_FILE_NAME.
unzip -p covers.zip $RANDOM_FILE_NAME > local-$RANDOM_FILE_NAME
ls -l local-$RANDOM_FILE_NAME
```




So yes, we can actually extract a subset of files from a zipped archive
stored on S3 using `mount-s3` efficiently!

```bash
aws s3 cp covers.zip s3://$BUCKET_NAME/
ls bucket/*.zip
unzip -p bucket/covers.zip $RANDOM_FILE_NAME > remote-$RANDOM_FILE_NAME
ls -l *$RANDOM_FILE_NAME
```




And yes, with great powers comes great responsibilities:

```bash
rm -fr bucket/
umount bucket
```




## Multipart upload 



S3 admits uploading multiple chunks and then automatically concatenate them into a single
one. Usually, this is used for uploading multiple parts of the same file in an efficient
way, but it can also be handy to unify different consecutive logs. Let's generate two
files of one megabyte to see how it works:

```bash
for i in $(seq 1 2)
do
    file=chunk${i}.txt
    touch $file
    while [ $(du -m $file | cut -f1) -lt 5 ]
    do     
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c $((1024*1024)) >> $file
    done
    printf "\nEND OF CHUNK $i.\n" >> $file
done
ls -lh chunk*.txt
```



Starting the uploading process requires an API call. In this case, we are going
to create a file named `morenumbers.txt`:

```bash
upload_id=$(aws s3api create-multipart-upload \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --query 'UploadId' \
  --output text)
echo Upload ID is $upload_id.
```



Once we upload all the chunks, we will need to list the [ETag](https://developer.mozilla.org/es/docs/Web/HTTP/Headers/ETag) of each one to generate the final file. Let's upload the first part, and then
accumulate the *ETag* in a variable:


```bash
parts=""

part_number=1
file=chunk${part_number}.txt
etag=$(aws s3api upload-part \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --part-number $part_number \
  --body $file \
  --upload-id $upload_id \
  --query 'ETag' \
  --output text)
echo Part etag: $etag.
parts="$parts{\"ETag\": $etag, \"PartNumber\": $part_number},"
echo Parts: $parts
```



Of course, in a real scenario we would have used a loop. But for learning the process it is probably
easier to just run the previous step again with the second chunk:

```bash
part_number=2
file=chunk${part_number}.txt
etag=$(aws s3api upload-part \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --part-number $part_number \
  --body $file \
  --upload-id $upload_id \
  --query 'ETag' \
  --output text)
echo Part etag: $etag.
parts="$parts{\"ETag\": $etag, \"PartNumber\": $part_number},"
echo Parts: $parts
```



Both parts have been uploaded, but the final result still doesn't exist:


```bash
aws s3api list-parts \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --upload-id $upload_id

aws s3 ls s3://$BUCKET_NAME | grep morenumbers.txt  # (empty)
```



To join all the chunks in a single file (and to free the space used by them) we can run
a `compleate-multipart-upload` call:


```bash
parts="{\"Parts\": [${parts%?}]}"
echo $parts | jq

aws s3api complete-multipart-upload \
  --multipart-upload "$parts" \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --upload-id $upload_id
```




The parts doesn't exist anymore, and now the final file appears in our list command:

```bash
aws s3api list-parts \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --upload-id $upload_id

aws s3 ls s3://$BUCKET_NAME | grep morenumbers.txt
aws s3 cp s3://$BUCKET_NAME/morenumbers.txt .
cat morenumbers.txt | grep "END OF CHUNK"
```



If anything goes wrong, it is very important to still free all the remaining information
that hasn't been concatenated. This task can be accomplished with:

```bash
aws s3api abort-multipart-upload \
  --bucket $BUCKET_NAME \
  --key morenumbers.txt \
  --upload-id $upload_id
```

