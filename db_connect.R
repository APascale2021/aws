library(DBI)
library(RPostgreSQL)
library(dbplyr)
library(yaml)
library(janitor)
library(aws.s3)

config <- yaml.load_file('config.yml')

# Establish connection to AWS environment
aws_creds <- config$awsaccount

Sys.setenv(
  AWS_ACCESS_KEY_ID = aws_creds$accesskey,
  AWS_SECRET_ACCESS_KEY = aws_creds$secretkey,
  AWS_REGION = 'us-east-1'
)

bucket <- "stocks-daily-ohlc"
s3_uid <- aws_creds$s3id

# Get list of bucket objects
obj_list <- data.table::rbindlist(get_bucket(bucket = bucket)) %>%
  filter(Owner==s3_uid) %>% 
  select(c(Key, LastModified))

# Download contents of s3 object to dataframe
df <- s3read_using(FUN = read.csv, bucket = bucket, object = obj_list$Key[[1]])

# Connect to database
db_creds <- config$postgres

con <- dbConnect(RPostgres::Postgres(),
                 dbname = db_creds$database,
                 host = db_creds$host,
                 port = db_creds$port,
                 user = db_creds$username,
                 password = db_creds$password)

# Create new table
queryString <- "
CREATE TABLE stocks (
  ticker varchar(16), 
  obs_date date, 
  open numeric(16, 3), 
  high numeric(16, 4), 
  low numeric(16, 4), 
  close numeric(16, 3), 
  volume bigint
);
"

dbExecute(con, queryString)
dbExistsTable(con, "stocks")

# Append dataframe to table
dbWriteTable(con, "stocks", df, overwrite = FALSE, append = TRUE)

# Query stored data
res <- dbGetQuery(con, "select * from stocks")

#dbRemoveTable(con, "stocks")

dbDisconnect(con)
