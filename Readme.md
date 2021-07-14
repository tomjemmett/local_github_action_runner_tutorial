Local GitHub Action Runner Tutorial
================
Tom Jemmett
14/07/2021

In this tutorial we will look to setup a local GitHub Action Runner to
run jobs within our local network when we commit changes to the main
branch in GitHub.

The basic premise will be we have some code that builds a data
warehouse. When we make changes to the codebase we will re-run the code
to update the data warehouse. Even though we will be storing the code in
a public repository, and the action will be triggered from GitHub, the
runner will be local and will not be leaking information.

We will use Sqlite as a database, but this could easily be switched to
whatever database server you are running.

## Setup the database

First, set up a connection to a Sqlite file.

``` r
my_dw <- "c:\\my_datawarehouse.db"
con <- dbConnect(SQLite(), my_dw)
```

We can now load some data in, let’s use a subset of the data from the
`ae_attendances` dataset from `{NHSRdatasets}`.

``` r
ae_df <- filter(ae_attendances, period < ymd(20180401))
ae_df
```

    ## # A tibble: 8,393 x 6
    ##    period     org_code type  attendances breaches admissions
    ##    <date>     <fct>    <fct>       <dbl>    <dbl>      <dbl>
    ##  1 2017-03-01 RF4      1           21289     2879       5060
    ##  2 2017-03-01 RF4      2             813       22          0
    ##  3 2017-03-01 RF4      other        2850        6          0
    ##  4 2017-03-01 R1H      1           30210     5902       6943
    ##  5 2017-03-01 R1H      2             807       11          0
    ##  6 2017-03-01 R1H      other       11352      136          0
    ##  7 2017-03-01 AD913    other        4381        2          0
    ##  8 2017-03-01 RYX      other       19562      258          0
    ##  9 2017-03-01 RQM      1           17414     2030       3597
    ## 10 2017-03-01 RQM      other        7817       86          0
    ## # ... with 8,383 more rows

We can now write this data to the database, and then select the count of
rows.

``` r
dbWriteTable(con, "ae_attendances", ae_df, overwrite = TRUE)

count(tbl(con, "ae_attendances"))
```

    ## # Source:   lazy query [?? x 1]
    ## # Database: sqlite 3.35.5 [C:\my_datawarehouse.db]
    ##       n
    ##   <int>
    ## 1  8393

Finally, disconnect from the database.

``` r
dbDisconnect(con)
```

## Create a GitHub repository

Next, we need to create a GitHub repository for our code. For this, I’m
going to use the `{usethis}` package, but you could just as well create
a repository manually.

``` r
usethis::use_github()
```

## Setting up local runner

First, go to the settings for your GitHub repository, then go to
“Actions” on the left hand settings pane, then click on the “Runners”
item that appears underneath “Actions” when you open it. (You should
also see “Actions” appear on the top menu, between “Pull Requests” and
“Projects”, we will come to this later, but this is where the “Actions”
appear when they are run.)

Choose the platform that you are installing the runner on and follow all
of the given steps to install and configure the runner for this
repository. In my case I am using Windows, but it will give you the
steps for Linux or macOS also. The rest of the tutorial assumes we are
running on Windows, adjust accordingly for your platform.

The config script will ask a bunch of questions, which for the purpose
of this tutorial I have just left as the default, but you may need to
change these in a production setting. In particular, whether you want to
run this job as a service or not. The default is “no”, so you will need
to manually start the runner.

Once you have configured the runner, if you go back to the “Runners”
page in GitHub you should see the self-hosted runner that you just
created, but it will say “Offline”. If you go back to the folder that
you installed the runner into you can run `.\run.cmd` to start the
runner. You should see a message that the runner has connected to
GitHub, and if you go back and refresh the “Runners” page you should see
this runner is now “Idle” with a green dot.

We will need to keep the command prompt open while we run this tutorial.
If we close it, the runner will stop and the actions will not run.

## Creating a workflow

### Hello World

First, let’s create the simplest possible workflow - a “Hello World”
example.

If we go to the “Actions” page (in the menu just under the repository
name), we will be taken to a page that allows us to create a new
workflow. For now, let’s select “Simple workflow”. We can then clear the
file and use the following:

    name: Hello World

    on:
      push:
        branches: [ main ]
      pull_request:
        branches: [ main ]

    jobs:
      hello_world:
        runs-on: self-hosted

        steps:
          - name: Hello World
            run: |
              echo "Hello World!"
            shell: cmd

This workflow will run on push and pull requests to the “main” branch,
will run on our runner that we created (it will run on any runner that
is available with a tag of “self-hosted”). Finally, it will run a step
which will simply print out “Hello World”.

If we save and commit this file directly to the main branch, then go
back to the actions tab we should see this action start, and then finish
successfully. If you go back to the command prompt you should see a
message showing that this job was picked up and ran successfully.

## Running R

The next step for me was to get the action to run R. You could choose
instead to run any other code or program that is installed on the
computer you have the runner installed on, for instance you could use
[`sqlcmd`](https://docs.microsoft.com/en-us/sql/ssms/scripting/sqlcmd-start-the-utility?view=sql-server-ver15)
to directly issue T-SQL statements to a Microsoft Sql Server database.

If you look at some of the actions for R (e.g.,
[R-CMD-check](https://github.com/r-lib/actions/blob/master/examples/check-full.yaml))
you will see two things:

1.  they “use” `r-lib/actions/setup-r@v1`: this will download and
    install R into that runner
2.  that they directly call the `RScript` shell

Now, the reason they run step 1 is the default GitHub action runners
(hosted by GitHub) are docker containers that do not have R installed,
so they have to add R in before it is usable. I don’t need to do this -
R is installed on the computer that I have installed the self-hosted
runner on.

However, I do not have R installed on the system path, so if I type
`RScript` into a command prompt I get:

    PS C:\> RScript
    RScript : The term 'RScript' is not recognized as the name of a cmdlet, function, script file, or operable program.
    Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
    At line:1 char:1
    + RScript
    + ~~~~~~~
        + CategoryInfo          : ObjectNotFound: (RScript:String) [], CommandNotFoundException
        + FullyQualifiedErrorId : CommandNotFoundException

Instead, what I will do is create a simple `.cmd` file which will itself
call `Rscript` with a given file. A bit inconvenient, if anyone knows
how to solve this I would be all ears!

***run\_update\_datawarehouse.cmd***

``` cmd
"c:\Program Files\R\R-4.1.0\bin\Rscript.exe" "update_datawarehouse.R"
```

I now need to create an R script to do what I want

***update\_datawarehouse.R.R***

``` r
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
```

***.github/workflows/r\_hello\_world.yml***

    name: R Hello World

    on:
      push:
        branches: [ main ]
      pull_request:
        branches: [ main ]

    jobs:
      r_hello_world:
        runs-on: self-hosted

        steps:
          - uses: actions/checkout@v2

          - name: R Hello World
            run: |
              run_hello_world.cmd
            shell: cmd

There is one important extra step for this workflow; an extra step is
added that uses “<action/checkout@v2>”. What this does is when the
runner starts it automatically grabs the latest commit from the
repository from the branch that triggered this action (in this case,
main). This is really important - if we don’t have this step then we
will not have the latest changes!

## Conclussions

GitHub actions are a great tool, and are super easy to run within your
own network so you do not expose data onto the public internet.
