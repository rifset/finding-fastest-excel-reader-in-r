# Working with Excel files in R: A Journey to Find the Fastest Reader

*Disclaimer: This is the iterated version of my old Linkedin [post](https://www.linkedin.com/pulse/benchmarking-xlsx-openxlsx-readxl-package-r-arif-setyawan/). I changed some codes and parameters in comparison to the old version.*

![cover.jpg](cover.jpg)

## Background

In my previous and current projects, I was working with Excel files. One of the tasks was to import an Excel file to another software, as in my case, it was R. At a glance, I know the `xlsx` package on R, and I thought it would be easy and quick to finish the task. Until I figured out that this simple importing task could be time-consuming. It is done quickly for small-sized data Excel files, yet not for larger ones. This problem led me to the curiosity of what is the fastest R package to import Excel files.

There are a few reasons I could not convert the Excel files to CSV files. One of the reasons is CSV cannot preserve long decimal values while I work decimals most of the time. I realize that importing CSV files is much faster (`fread()` in the `data.table` package is the best) and less memory-consuming than Excel, but in this case, I need Excel.

## Finding available tools

I found five R packages that can be used, such as `xlsx`, `openxlsx`, `readxl`, `gdata`, and `XLConnect`. Unfortunately, the `XLConnect` package could not be loaded on my computer since it builds in an older version than mine, and the gdata package was too complicated to install its Perl component. Thus, the remaining available packages to be benchmarked are `xlsx`, `openxlsx`, and `readxl`.

## Benchmarking

There are packages in R to do benchmarking like the `microbenchmark` package, which evaluates an expression multiple times with a time precision of up to nanoseconds. I decided to do my version of benchmarking because I want to know which package is the fastest to import Excel files on dynamic datasets, instead of evaluating with the same dataset but done many times. So, I created some artificial datasets by subsetting and slicing data from the `superai_retail_dataset` on [Kaggle](https://www.kaggle.com/chinnatiptaemkaeo/superai-retail-dataset). The datasets I created are combinations of five rows and four columns options with ten variations of each combined option.

### Data preparation

```r
library(data.table)
library(tidyverse)
library(openxlsx)

# Importing data ----------------------------------------------------------

supermarket <- fread("Supermarket Data.csv", na.strings = c("", "NA"))
dim(supermarket)

# Creating artificial data ------------------------------------------------

supermarket_procs <- supermarket %>% 
  left_join(
    supermarket %>% 
      group_by(BASKET_ID) %>% 
      summarize(TOTAL_SPEND_PER_BASKET = sum(SPEND)),
    by = "BASKET_ID"
  ) %>% 
  mutate(PERCENT_SPEND_PER_BASKET = SPEND/TOTAL_SPEND_PER_BASKET) %>% 
  left_join(
    supermarket %>% 
      group_by(PROD_CODE) %>% 
      summarize(across(QUANTITY, list(MEAN = mean, STDEV = sd, MIN = min, MAX = max),
                       .names = "{.fn}_{.col}")),
    by = "PROD_CODE"
  )

# Export artificial data --------------------------------------------------

n.columns <- c(5, 10, 15, 20)
n.rows <- c(100, 500, 1000, 5000, 10000)
set.seed(123)
for (k in 1:4) {
  for (j in 1:5) {
    cwb <- createWorkbook()
    for (i in 1:10) {
      supermarket.tmp <- supermarket_procs %>% 
        select_at(sample(c(1:ncol(supermarket_procs)), n.columns[k])) %>% 
        slice(sample(c(1:nrow(supermarket_procs)), n.rows[j]))
      addWorksheet(cwb, paste0("Sheet", i))
      writeDataTable(cwb, sheet = paste0("Sheet", i), x = supermarket.tmp)
    }
    saveWorkbook(cwb, file = paste0(n.columns[k], "col", n.rows[j], "row", ".xlsx"))
  }
}
```

## Benchmarking process

```r
## Starting from here, please restart the R session

library(data.table)
library(dplyr)

n.columns <- factor(c(5, 10, 15, 20), levels = c(5, 10, 15, 20))
n.rows <- factor(c(100, 500, 1000, 5000, 10000), levels = c(100, 500, 1000, 5000, 10000))

# Benchmarking READXL -----------------------------------------------------

library(readxl)
readxl.dt <- data.table(cols = factor(), rows = factor(), elapsed = numeric())
for (k in 1:4) {
  for (j in 1:5) {
    for (i in 1:10) {
      readxl.dt <- bind_rows(readxl.dt, data.table(
        cols = n.columns[k],
        rows = n.rows[j],
        elapsed = system.time(read_excel(
          paste0(n.columns[k], "col", n.rows[j], "row", ".xlsx"), sheet = i))[3]
      )
      )
    }
  }
}
detach("package:readxl", unload = TRUE)

# Benchmarking OPENXLSX ---------------------------------------------------

library(openxlsx)
openxlsx.dt <- data.table(cols = factor(), rows = factor(), elapsed = numeric())
for (k in 1:4) {
  for (j in 1:5) {
    for (i in 1:10) {
      openxlsx.dt <- bind_rows(openxlsx.dt, data.table(
        cols = n.columns[k],
        rows = n.rows[j],
        elapsed = system.time(read.xlsx(
          paste0(n.columns[k], "col", n.rows[j], "row", ".xlsx"), sheet = i))[3]
      )
      )
    }
  }
}
detach("package:openxlsx", unload = TRUE)

# Benchmarking XLSX -------------------------------------------------------

options(java.parameters = "-Xmx4000m")
library(xlsx)
xlsx.dt <- data.table(cols = factor(), rows = factor(), elapsed = numeric())
for (k in 1:4) {
  for (j in 1:5) {
    for (i in 1:10) {
      xlsx.dt <- bind_rows(xlsx.dt, data.table(
        cols = n.columns[k],
        rows = n.rows[j],
        elapsed = system.time(xlsx::read.xlsx(
          paste0(n.columns[k], "col", n.rows[j], "row", ".xlsx"), sheetIndex = i))[3]
      )
      )
    }
  }
}
detach("package:xlsx", unload = TRUE)

# Wrapping up benchrmarking result ---------------------------------------

all.dt <- list(xlsx = xlsx.dt, openxlsx = openxlsx.dt, readxl = readxl.dt)
all.dt <- rbindlist(all.dt, idcol = "package")
```

### Summarizing

```r
all.dt.summary <- all.dt %>% 
  mutate(package = factor(package, levels = c("xlsx", "openxlsx", "readxl"))) %>% 
  group_by_at(-4) %>% 
  summarize(across(elapsed, list(mean = mean, sd = sd, min = min,
                                 median = median, max = max),
                   .names = "{.fn}.{.col}"), .groups = "keep") %>% 
  ungroup()
```

### Visualization

```r
library(ggplot2)

plot.median <- all.dt.summary %>% 
  ggplot(aes(x = rows, y = median.elapsed, group = package, color = package)) +
  geom_line() +
  geom_point() +
  facet_wrap(~cols, labeller = "label_both") +
  labs(title = "Elapsed Time", x = "Rows", y = "Time (second)",
       color = "Package", subtitle = "Median")

plot.mean <- all.dt.summary %>% 
  ggplot(aes(x = rows, y = mean.elapsed, group = package, color = package)) +
  geom_line() +
  geom_point() +
  facet_wrap(~cols, labeller = "label_both") +
  labs(title = "Elapsed Time", x = "Rows", y = "Time (second)",
       color = "Package", subtitle = "Mean")
```

## Result

### Table view

Values shown are elapsed time in second.
<details> 
  <summary>Click to see the full table</summary>
<table>
 <thead>
  <tr>
   <th style="text-align:left;"> Package Name </th>
   <th style="text-align:left;"> Number of Columns </th>
   <th style="text-align:left;"> Number of Rows </th>
   <th style="text-align:right;"> Mean </th>
   <th style="text-align:right;"> St. Dev </th>
   <th style="text-align:right;"> Min </th>
   <th style="text-align:right;"> Median </th>
   <th style="text-align:right;"> Max </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.175 </td>
   <td style="text-align:right;"> 0.1056462 </td>
   <td style="text-align:right;"> 0.09 </td>
   <td style="text-align:right;"> 0.140 </td>
   <td style="text-align:right;"> 0.46 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.442 </td>
   <td style="text-align:right;"> 0.0373571 </td>
   <td style="text-align:right;"> 0.39 </td>
   <td style="text-align:right;"> 0.440 </td>
   <td style="text-align:right;"> 0.52 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.875 </td>
   <td style="text-align:right;"> 0.0834333 </td>
   <td style="text-align:right;"> 0.71 </td>
   <td style="text-align:right;"> 0.910 </td>
   <td style="text-align:right;"> 0.99 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 4.488 </td>
   <td style="text-align:right;"> 0.5512370 </td>
   <td style="text-align:right;"> 3.49 </td>
   <td style="text-align:right;"> 4.610 </td>
   <td style="text-align:right;"> 5.24 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 9.138 </td>
   <td style="text-align:right;"> 0.9399858 </td>
   <td style="text-align:right;"> 7.67 </td>
   <td style="text-align:right;"> 9.435 </td>
   <td style="text-align:right;"> 10.39 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.186 </td>
   <td style="text-align:right;"> 0.0107497 </td>
   <td style="text-align:right;"> 0.17 </td>
   <td style="text-align:right;"> 0.190 </td>
   <td style="text-align:right;"> 0.20 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.894 </td>
   <td style="text-align:right;"> 0.1010171 </td>
   <td style="text-align:right;"> 0.74 </td>
   <td style="text-align:right;"> 0.895 </td>
   <td style="text-align:right;"> 1.09 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 1.683 </td>
   <td style="text-align:right;"> 0.1141198 </td>
   <td style="text-align:right;"> 1.53 </td>
   <td style="text-align:right;"> 1.660 </td>
   <td style="text-align:right;"> 1.88 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 9.125 </td>
   <td style="text-align:right;"> 1.5940044 </td>
   <td style="text-align:right;"> 7.61 </td>
   <td style="text-align:right;"> 8.655 </td>
   <td style="text-align:right;"> 12.91 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 21.888 </td>
   <td style="text-align:right;"> 2.1073142 </td>
   <td style="text-align:right;"> 19.02 </td>
   <td style="text-align:right;"> 21.355 </td>
   <td style="text-align:right;"> 25.32 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.269 </td>
   <td style="text-align:right;"> 0.0445845 </td>
   <td style="text-align:right;"> 0.23 </td>
   <td style="text-align:right;"> 0.260 </td>
   <td style="text-align:right;"> 0.39 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 1.205 </td>
   <td style="text-align:right;"> 0.0782091 </td>
   <td style="text-align:right;"> 1.09 </td>
   <td style="text-align:right;"> 1.205 </td>
   <td style="text-align:right;"> 1.34 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 2.358 </td>
   <td style="text-align:right;"> 0.1348909 </td>
   <td style="text-align:right;"> 2.19 </td>
   <td style="text-align:right;"> 2.365 </td>
   <td style="text-align:right;"> 2.53 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 13.309 </td>
   <td style="text-align:right;"> 0.6814111 </td>
   <td style="text-align:right;"> 11.93 </td>
   <td style="text-align:right;"> 13.570 </td>
   <td style="text-align:right;"> 14.07 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 29.381 </td>
   <td style="text-align:right;"> 1.4177639 </td>
   <td style="text-align:right;"> 27.62 </td>
   <td style="text-align:right;"> 29.485 </td>
   <td style="text-align:right;"> 31.59 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.333 </td>
   <td style="text-align:right;"> 0.0149443 </td>
   <td style="text-align:right;"> 0.31 </td>
   <td style="text-align:right;"> 0.330 </td>
   <td style="text-align:right;"> 0.35 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 1.496 </td>
   <td style="text-align:right;"> 0.0620394 </td>
   <td style="text-align:right;"> 1.42 </td>
   <td style="text-align:right;"> 1.495 </td>
   <td style="text-align:right;"> 1.61 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 2.990 </td>
   <td style="text-align:right;"> 0.0905539 </td>
   <td style="text-align:right;"> 2.86 </td>
   <td style="text-align:right;"> 2.960 </td>
   <td style="text-align:right;"> 3.14 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 18.016 </td>
   <td style="text-align:right;"> 1.1070501 </td>
   <td style="text-align:right;"> 16.47 </td>
   <td style="text-align:right;"> 17.795 </td>
   <td style="text-align:right;"> 20.06 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> xlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 39.458 </td>
   <td style="text-align:right;"> 2.4949095 </td>
   <td style="text-align:right;"> 36.94 </td>
   <td style="text-align:right;"> 38.710 </td>
   <td style="text-align:right;"> 45.80 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.060 </td>
   <td style="text-align:right;"> 0.0105409 </td>
   <td style="text-align:right;"> 0.05 </td>
   <td style="text-align:right;"> 0.060 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.058 </td>
   <td style="text-align:right;"> 0.0078881 </td>
   <td style="text-align:right;"> 0.04 </td>
   <td style="text-align:right;"> 0.060 </td>
   <td style="text-align:right;"> 0.07 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.080 </td>
   <td style="text-align:right;"> 0.0066667 </td>
   <td style="text-align:right;"> 0.07 </td>
   <td style="text-align:right;"> 0.080 </td>
   <td style="text-align:right;"> 0.09 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.166 </td>
   <td style="text-align:right;"> 0.0142984 </td>
   <td style="text-align:right;"> 0.14 </td>
   <td style="text-align:right;"> 0.170 </td>
   <td style="text-align:right;"> 0.19 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.296 </td>
   <td style="text-align:right;"> 0.0164655 </td>
   <td style="text-align:right;"> 0.28 </td>
   <td style="text-align:right;"> 0.290 </td>
   <td style="text-align:right;"> 0.33 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.056 </td>
   <td style="text-align:right;"> 0.0107497 </td>
   <td style="text-align:right;"> 0.04 </td>
   <td style="text-align:right;"> 0.055 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.085 </td>
   <td style="text-align:right;"> 0.0070711 </td>
   <td style="text-align:right;"> 0.08 </td>
   <td style="text-align:right;"> 0.080 </td>
   <td style="text-align:right;"> 0.10 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.105 </td>
   <td style="text-align:right;"> 0.0177951 </td>
   <td style="text-align:right;"> 0.09 </td>
   <td style="text-align:right;"> 0.100 </td>
   <td style="text-align:right;"> 0.14 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.281 </td>
   <td style="text-align:right;"> 0.0144914 </td>
   <td style="text-align:right;"> 0.26 </td>
   <td style="text-align:right;"> 0.280 </td>
   <td style="text-align:right;"> 0.30 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.456 </td>
   <td style="text-align:right;"> 0.0298887 </td>
   <td style="text-align:right;"> 0.42 </td>
   <td style="text-align:right;"> 0.460 </td>
   <td style="text-align:right;"> 0.50 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.054 </td>
   <td style="text-align:right;"> 0.0126491 </td>
   <td style="text-align:right;"> 0.04 </td>
   <td style="text-align:right;"> 0.050 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.082 </td>
   <td style="text-align:right;"> 0.0103280 </td>
   <td style="text-align:right;"> 0.07 </td>
   <td style="text-align:right;"> 0.080 </td>
   <td style="text-align:right;"> 0.10 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.118 </td>
   <td style="text-align:right;"> 0.0091894 </td>
   <td style="text-align:right;"> 0.11 </td>
   <td style="text-align:right;"> 0.115 </td>
   <td style="text-align:right;"> 0.13 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.372 </td>
   <td style="text-align:right;"> 0.0204396 </td>
   <td style="text-align:right;"> 0.34 </td>
   <td style="text-align:right;"> 0.365 </td>
   <td style="text-align:right;"> 0.41 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.736 </td>
   <td style="text-align:right;"> 0.0353396 </td>
   <td style="text-align:right;"> 0.69 </td>
   <td style="text-align:right;"> 0.730 </td>
   <td style="text-align:right;"> 0.82 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.064 </td>
   <td style="text-align:right;"> 0.0069921 </td>
   <td style="text-align:right;"> 0.06 </td>
   <td style="text-align:right;"> 0.060 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.101 </td>
   <td style="text-align:right;"> 0.0099443 </td>
   <td style="text-align:right;"> 0.09 </td>
   <td style="text-align:right;"> 0.105 </td>
   <td style="text-align:right;"> 0.11 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.138 </td>
   <td style="text-align:right;"> 0.0091894 </td>
   <td style="text-align:right;"> 0.12 </td>
   <td style="text-align:right;"> 0.140 </td>
   <td style="text-align:right;"> 0.15 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.440 </td>
   <td style="text-align:right;"> 0.0149071 </td>
   <td style="text-align:right;"> 0.42 </td>
   <td style="text-align:right;"> 0.440 </td>
   <td style="text-align:right;"> 0.46 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> openxlsx </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.961 </td>
   <td style="text-align:right;"> 0.0762234 </td>
   <td style="text-align:right;"> 0.89 </td>
   <td style="text-align:right;"> 0.925 </td>
   <td style="text-align:right;"> 1.11 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.016 </td>
   <td style="text-align:right;"> 0.0051640 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.02 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.017 </td>
   <td style="text-align:right;"> 0.0067495 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.026 </td>
   <td style="text-align:right;"> 0.0107497 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.030 </td>
   <td style="text-align:right;"> 0.04 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.039 </td>
   <td style="text-align:right;"> 0.0087560 </td>
   <td style="text-align:right;"> 0.03 </td>
   <td style="text-align:right;"> 0.040 </td>
   <td style="text-align:right;"> 0.05 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 5 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.057 </td>
   <td style="text-align:right;"> 0.0115950 </td>
   <td style="text-align:right;"> 0.04 </td>
   <td style="text-align:right;"> 0.055 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.022 </td>
   <td style="text-align:right;"> 0.0063246 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.0081650 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.029 </td>
   <td style="text-align:right;"> 0.0056765 </td>
   <td style="text-align:right;"> 0.02 </td>
   <td style="text-align:right;"> 0.030 </td>
   <td style="text-align:right;"> 0.04 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.058 </td>
   <td style="text-align:right;"> 0.0103280 </td>
   <td style="text-align:right;"> 0.04 </td>
   <td style="text-align:right;"> 0.060 </td>
   <td style="text-align:right;"> 0.08 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.092 </td>
   <td style="text-align:right;"> 0.0122927 </td>
   <td style="text-align:right;"> 0.07 </td>
   <td style="text-align:right;"> 0.090 </td>
   <td style="text-align:right;"> 0.11 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.016 </td>
   <td style="text-align:right;"> 0.0051640 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.02 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.023 </td>
   <td style="text-align:right;"> 0.0067495 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.030 </td>
   <td style="text-align:right;"> 0.0000000 </td>
   <td style="text-align:right;"> 0.03 </td>
   <td style="text-align:right;"> 0.030 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.087 </td>
   <td style="text-align:right;"> 0.0105935 </td>
   <td style="text-align:right;"> 0.08 </td>
   <td style="text-align:right;"> 0.080 </td>
   <td style="text-align:right;"> 0.11 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 15 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.143 </td>
   <td style="text-align:right;"> 0.0067495 </td>
   <td style="text-align:right;"> 0.14 </td>
   <td style="text-align:right;"> 0.140 </td>
   <td style="text-align:right;"> 0.16 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:right;"> 0.018 </td>
   <td style="text-align:right;"> 0.0078881 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.020 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 500 </td>
   <td style="text-align:right;"> 0.023 </td>
   <td style="text-align:right;"> 0.0082327 </td>
   <td style="text-align:right;"> 0.01 </td>
   <td style="text-align:right;"> 0.025 </td>
   <td style="text-align:right;"> 0.03 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 1000 </td>
   <td style="text-align:right;"> 0.040 </td>
   <td style="text-align:right;"> 0.0081650 </td>
   <td style="text-align:right;"> 0.03 </td>
   <td style="text-align:right;"> 0.040 </td>
   <td style="text-align:right;"> 0.05 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 5000 </td>
   <td style="text-align:right;"> 0.101 </td>
   <td style="text-align:right;"> 0.0099443 </td>
   <td style="text-align:right;"> 0.09 </td>
   <td style="text-align:right;"> 0.105 </td>
   <td style="text-align:right;"> 0.11 </td>
  </tr>
  <tr>
   <td style="text-align:left;"> readxl </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 10000 </td>
   <td style="text-align:right;"> 0.192 </td>
   <td style="text-align:right;"> 0.0193218 </td>
   <td style="text-align:right;"> 0.17 </td>
   <td style="text-align:right;"> 0.190 </td>
   <td style="text-align:right;"> 0.22 </td>
  </tr>
</tbody>
</table>
</body>
</html>
</details>

### Chart view

![comparison-plot](comparison-plot.png)

As the number of rows and columns increased, the elapsed time rose. The elapsed time of the `xlsx` package is growing exponentially, while both `openxlsx` and `readxl` packages tend to be more stable. After doing some research through the net, the `openxlsx` is faster because it does not depend on Java while the `xlsx` package does. Though the elapsed time of `openxlsx` and `readxl` is not much different, `readxl` is faster than `openxlsx`. Even with the most "complex" Excel file, the `readxl` package running time is less than 0.2 seconds on average! Wow!

## Final thoughts

From this mini research, I learned that the `readxl` package is the fastest to import Excel files into R. Despite its performance on importing, the package does not provide any export command yet is available on a different but related package called `writexl`. However, the `openxlsx` package does provide an export command that makes this package more compact. Finally, it’s up to us to use which package depend on our needs. Thank you for reading this article, see you in the other writing!

> *Have you opened any Excel files today? :)*

## Reference

Taemkaeo, C. (2020). superai_retail_dataset, Version 2. Retrieved October 21, 2020 from [https://www.kaggle.com/datasets/chinnatiptaemkaeo/superai-retail-dataset](https://www.kaggle.com/datasets/chinnatiptaemkaeo/superai-retail-dataset).
