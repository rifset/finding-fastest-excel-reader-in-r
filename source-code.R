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


# Benchmarking ------------------------------------------------------------

## Starting from here, please restart your R session

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

# Summarizing -------------------------------------------------------------

all.dt.summary <- all.dt %>% 
  mutate(package = factor(package, levels = c("xlsx", "openxlsx", "readxl"))) %>% 
  group_by_at(-4) %>% 
  summarize(across(elapsed, list(mean = mean, sd = sd, min = min,
                                 median = median, max = max),
                   .names = "{.fn}.{.col}"), .groups = "keep") %>% 
  ungroup()
all.dt.summary

# Visualization -----------------------------------------------------------

library(ggplot2)

plot.median <- all.dt.summary %>% 
  ggplot(aes(x = rows, y = median.elapsed, group = package, color = package)) +
  geom_line() +
  geom_point() +
  facet_wrap(~cols, labeller = "label_both") +
  labs(title = "Elapsed Time", x = "Rows", y = "Time (second)",
       color = "Package", subtitle = "Median")
print(plot.median)

plot.mean <- all.dt.summary %>% 
  ggplot(aes(x = rows, y = mean.elapsed, group = package, color = package)) +
  geom_line() +
  geom_point() +
  facet_wrap(~cols, labeller = "label_both") +
  labs(title = "Elapsed Time", x = "Rows", y = "Time (second)",
       color = "Package", subtitle = "Mean")
print(plot.mean)
