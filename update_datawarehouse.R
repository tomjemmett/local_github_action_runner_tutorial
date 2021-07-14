library(tidyverse)
library(lubridate)
library(DBI)
library(RSQLite)
library(NHSRdatasets)

my_dw <- "c:\\my_datawarehouse.db"
con <- dbConnect(SQLite(), my_dw)

on.exit(dbDisconnect(con))

ae_df <- filter(ae_attendances, period >= ymd(20180401))
dbWriteTable(con, "ae_attendances", ae_df, append = TRUE)

n <- tbl(con, "ae_attendances") |> count() |> collect() |> pull(n)

cat("The table now has", n, "rows\n")
