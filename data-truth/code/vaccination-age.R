# European age-stratified vaccination data
library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(ggrepel)
library(lubridate)

plot_vaccination_by_age <- function(location_codes = NULL) {

  # Set up ------------------------------------------------------------------
  # date conversion for ecdc data
  date_series <- tibble(date = seq.Date(from = as.Date("2020-01-01"),
                                        by = 7, to = Sys.Date()),
                        week = isoweek(date),
                        year = isoyear(date),
                        yearweek = paste0(year, "-W", ifelse(week < 10, "0", ""), week)) %>%
    select(yearweek, date)

  if (is.null(location_codes)) {
    # Get 32 Euro hub locations
    location_codes <- read_csv("https://raw.githubusercontent.com/covid19-forecast-hub-europe/covid19-scenario-hub-europe/main/data-locations/locations_eu.csv") %>%
      select("location_name", "location", "population") %>%
      pull(unique(location))
  }

  # Get vaccination data by age ------------------------------------------------
  vax_url <- "https://opendata.ecdc.europa.eu/covid19/vaccine_tracker/csv/data.csv"
  # Source: ECDC (https://www.ecdc.europa.eu/en/publications-data/data-covid-19-vaccination-eu-eea)
  # - Note age data not available for Greece (GR), Netherlands (NL), United Kingdom (GB)
  vax_age_raw <- vroom::vroom(vax_url)

  # Clean
  vax_age <- vax_age_raw %>%
    # keep only national level data
    filter(Region == ReportingCountry &
             ReportingCountry %in% location_codes) %>%
    # tidy names, dates
    select(
      yearweek = YearWeekISO,
      location = ReportingCountry,
      pop_group = TargetGroup,
      pop_group_denom = Denominator,
      pop_country_denom = Population,
      vaccine = Vaccine,
      dose_1 = FirstDose,
      dose_2 = SecondDose,
      dose_3 = DoseAdditional1,
      dose_4 = DoseAdditional2,
      dose_0 = UnknownDose
    ) %>%
    left_join(date_series, by = "yearweek") %>%
    pivot_longer(cols = starts_with("dose"),
                 names_to = "dose", values_to = "value") %>%
    mutate(sixty_plus = pop_group %in% c(
      "1_Age60+", "Age60_69", "Age70_79", "Age80+"),
      dose = factor(dose,
                    levels = paste0("dose_", 0:4),
                    labels = c("Unknown", "Primary 1", "Primary 2",
                               "Booster 1", "Booster 2"),
                    ordered = TRUE))

  # keep only 60+ and all pop groups ------------------------
  # denominators
  denoms <- vax_age %>%
    group_by(location, sixty_plus) %>%
    filter((pop_group == "ALL" | sixty_plus) &
             date == max(date)) %>%
    distinct(location, pop_group, pop_group_denom) %>%
    summarise(pop_group_denom = sum(pop_group_denom))

  # vaccinations
  vax_age_60 <- vax_age %>%
    filter(pop_group == "ALL" | sixty_plus) %>%
    group_by(date, location, dose, sixty_plus) %>%
    summarise(value = sum(value, na.rm = TRUE),
              .groups = "drop") %>%
    left_join(denoms, by = c("location", "sixty_plus")) %>%
    group_by(location, dose, sixty_plus) %>%
    mutate(value_tot = cumsum(value),
           value_tot_p = value_tot / pop_group_denom * 100) %>%
    ungroup() %>%
    mutate(value_tot_p = ifelse(value_tot_p > 100, 100, value_tot_p),
           vax_group = cut(value_tot_p,
                           breaks = c(-Inf, 25*(0:4)),
                           include_lowest = TRUE,
                           ordered_result = TRUE))

  # plot distribution of vaccinations %
  dose_cols <- c("#999999", "#f1c232", "#6aa84f", "#0b5394", "#741b47")
  names(dose_cols) <- levels(vax_age$dose)

  plot_vax_age <- vax_age_60 |>
    select(location, dose, date, sixty_plus, value_tot_p) %>%
    group_by(location) |>
    filter(date == max(date) &
             dose != "Unknown") |>
    pivot_wider(names_from = sixty_plus,
                names_prefix = "sixty_plus_",
                values_from = value_tot_p) |>
    ungroup() |>
    # mutate(alpha_value = )
    ggplot(aes(x = sixty_plus_FALSE,
               y = sixty_plus_TRUE,
               col = dose)) +
    geom_point() +
    geom_abline(intercept = 1, lty = 2, alpha = 0.5) +
    geom_text_repel(aes(label = location),
                    max.overlaps = 50,
                    size = 3, min.segment.length = 0.3) +
    labs(x = "% total population vaccinated",
         y = "% 60+ population vaccinated",
         col = "Dose",
         caption = "Vaccination % among 60+ population, relative to total population") +
    scale_color_manual(values = dose_cols) +
    theme_bw() +
    theme(legend.position = "bottom")

  return(plot_vax_age)
}


  # First booster dose for 60 plus age group --------------------------------
  # - note: each country has either "Age60+" or narrower age bands (but not both)
  # vax_60plus_boosters <- vax_age_timeseries %>%
  #   filter(dose == "dose_booster_1") %>%
  #   mutate(pop_group = ifelse(pop_group %in% c("1_Age60+",
  #                                            "Age60_69", "Age70_79", "Age80+"),
  #                       "sixty_plus",
  #                       ifelse(pop_group == "ALL", "all", NA))) %>%
  #   # keep totals and 60+ age group doses
  #   filter(!is.na(pop_group)) %>%
  #   group_by(location, pop_group) %>%
  #   summarise(value = sum(value, na.rm = TRUE), .groups = "keep") %>%
  #   pivot_wider(values_from = value,
  #               names_from = pop_group,
  #               names_prefix = "booster1_") %>%
  #   # add proportion of first boosters given to 60+ group
  #   mutate(booster1_sixty_plus_pp = booster1_sixty_plus / booster1_all)
  #
  # # Save --------------------------------------------------------------------
  # write_csv(vax_age_timeseries,
  #           here::here("data-truth", "data", "vaccination-age-week.csv"))
  #
  # write_csv(vax_60plus_boosters,
  #           here::here("data-truth", "data", "vaccination-60plus-booster1.csv"))

