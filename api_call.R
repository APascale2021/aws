library(tidyverse)
library(httr2)
library(yaml)
library(config)
library(jsonlite)
library(lubridate)
library(janitor)
library(aws.s3)

config <- yaml.load_file('config.yml')

params <- list("X-RapidAPI-Key" = config$apiserver['apikey'][[1]],
              "X-RapidAPI-Host" = config$apiserver['host'][[1]])

ticker <- "MSFT"

queryString <- list("function" = "TIME_SERIES_DAILY",
                    "symbol" = ticker,
                    "outputsize" = "compact",
                    "datatype" = "json")

req <- request(config$apiserver['requesturl'][[1]]) %>%
  req_headers(!!!params) %>% 
  req_url_query(!!!queryString)

req  %>%
  req_dry_run()

resp <- req_perform(req)

resp %>% resp_status_desc()
resp %>% resp_content_type()

content <- httr2::resp_body_json(resp)
symbol <- content$`Meta Data`$`2. Symbol`
last_updated <- as.Date(content$`Meta Data`$`3. Last Refreshed`)

data <- content$`Time Series (Daily)`

df <- do.call(rbind, lapply(data, data.frame))
cols <- as.vector( sapply(
          sapply(make_clean_names(colnames(df)), function(x) strsplit(x, '_')),
            function(y) y[length(y)] )
          )

colnames(df) <- cols
df <- cbind('obs_date' = rownames(df), df)
rownames(df) <- NULL
df <- as_tibble(df)

df$obs_date <- as.Date(df$obs_date)
df <- df %>% mutate(across(where(is.character), as.numeric))
df <- cbind('ticker' = symbol, df)

sapply(df, class)
df

Sys.setenv(
  AWS_ACCESS_KEY_ID = config$awsaccount['accesskey'][[1]],
  AWS_SECRET_ACCESS_KEY = config$awsaccount['secretkey'][[1]],
  AWS_REGION = 'us-east-1'
)

bucket <- "stocks-daily-ohlc"

s3write_using(df,
              FUN = write.csv,
              bucket = bucket,
              object = paste0(symbol,'.csv'),
              row.names = FALSE)
