library(tidyverse)
library(httr2)
library(yaml)
library(config)
library(jsonlite)
library(lubridate)
library(janitor)
library(aws.s3)

config <- yaml.load_file('config.yml')
ticker <- "MSFT"

# Establish API call parameters
url <- config$apiserver['requesturl'][[1]]
headers <- list("X-RapidAPI-Key" = config$apiserver['apikey'][[1]],
              "X-RapidAPI-Host" = config$apiserver['host'][[1]])

params <- list("function" = "TIME_SERIES_DAILY",
              "symbol" = ticker,
              "outputsize" = "compact",
              "datatype" = "json")

# Build request connection
req <- request(url) %>%
  req_headers(!!!headers) %>% 
  req_url_query(!!!params)

# View request syntax
req  %>%
  req_dry_run()

# GET request
resp <- req_perform(req)

resp %>% resp_status_desc()
resp %>% resp_content_type()

# convert response to JSON
content <- httr2::resp_body_json(resp)

# extract metadata
symbol <- content$`Meta Data`$`2. Symbol`
last_updated <- as.Date(content$`Meta Data`$`3. Last Refreshed`)

# get JSON body content
data <- content$`Time Series (Daily)`

# convert JSON to dataframe
df <- do.call(rbind, lapply(data, data.frame))

# clean column names
cols <- as.vector( sapply(
          sapply(make_clean_names(colnames(df)), function(x) strsplit(x, '_')),
            function(y) y[length(y)] )
          )
colnames(df) <- cols

# change data to type numeric
df <- df %>% mutate(across(where(is.character), as.numeric))

# make index with observation date into a new column with datetime format
df <- cbind('obs_date' = rownames(df), df)
rownames(df) <- NULL
df$obs_date <- as.Date(df$obs_date)

# copy stock ticker into new column
df <- cbind('ticker' = symbol, df)

head(df, n=10)
sapply(df, class)

# Establish connection to AWS environment
Sys.setenv(
  AWS_ACCESS_KEY_ID = config$awsaccount['accesskey'][[1]],
  AWS_SECRET_ACCESS_KEY = config$awsaccount['secretkey'][[1]],
  AWS_REGION = 'us-east-1'
)

bucket <- "stocks-daily-ohlc"

# write dataframe to s3 bucket as CSV
s3write_using(df,
              FUN = write.csv,
              bucket = bucket,
              object = paste0(symbol,'.csv'),
              row.names = FALSE)
