# cl_crash_join() and cl_crash_rates() on synthetic lanes and crashes.

lanes_two <- function() {
  # a 1 km protected lane along y = 39.70 and a 1 km painted lane along y = 39.71
  sf::st_sf(
    osm_id = c("p", "l"),
    name = c("Protected St", "Painted St"),
    facility_type = factor(c("protected_lane", "painted_lane"), levels = cl_facility_levels()),
    install_year = c(2021L, NA),
    exposure = c(1000, 100),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(-105.000, 39.70), c(-104.98832, 39.70))),
      sf::st_linestring(rbind(c(-105.000, 39.71), c(-104.98832, 39.71))),
      crs = 4326
    )
  )
}

crashes_pts <- function() {
  pt <- function(lon, lat) sf::st_point(c(lon, lat))
  sf::st_sf(
    source_id = as.character(1:6),
    year = c(2022L, 2022L, 2023L, 2023L, 2024L, 2024L),
    severity = factor(c("serious", "none", "fatal", "minor", "none", "serious"), levels = cyclelanes:::.crash_severity_levels),
    location_type = c("intersection", "mid_block", "mid_block", "mid_block", "intersection", "unknown"),
    n_fatal = c(0L, 0L, 1L, 0L, 0L, 0L),
    n_serious = c(1L, 0L, 0L, 0L, 0L, 1L),
    geometry = sf::st_sfc(
      pt(-104.995, 39.70005),   # 5 m from the protected lane
      pt(-104.992, 39.70010),   # 11 m from the protected lane
      pt(-104.995, 39.71005),   # near the painted lane
      pt(-104.990, 39.71),      # on the painted lane
      pt(-104.995, 39.75),      # far from anything
      pt(-104.995, 39.7002),    # 22 m from the protected lane
      crs = 4326
    )
  )
}

test_that("crashes snap to the nearest facility within tolerance", {
  j <- cl_crash_join(lanes_two(), crashes_pts(), tolerance = 25)
  expect_s3_class(j, "cl_crash_join")
  cr <- j$crashes
  expect_equal(as.character(cr$facility_type), c("protected_lane", "protected_lane", "painted_lane",
                                                  "painted_lane", "none", "protected_lane"))
  expect_true(is.na(cr$facility_row[5]))
  expect_true(all(cr$snap_dist_m[-5] <= 25))
  fa <- j$facilities
  expect_equal(fa$n_crashes, c(3L, 2L))
  expect_equal(fa$n_serious, c(2L, 0L))
  expect_equal(fa$n_fatal, c(0L, 1L))
  expect_output(print(j), "5 within 25 m")

  tight <- cl_crash_join(lanes_two(), crashes_pts(), tolerance = 8)
  expect_equal(sum(!is.na(tight$crashes$facility_row)), 3L)
})

test_that("rates use kilometre-years, split intersection from mid-block, and honour install_year and exposure", {
  j <- cl_crash_join(lanes_two(), crashes_pts(), tolerance = 25)
  r <- cl_crash_rates(j, years = 2022:2024)
  expect_true(all(c("facility_type", "location_type", "length_km", "km_years", "n_crashes",
                    "n_serious_fatal", "crashes_per_km_year", "serious_fatal_per_km_year",
                    "crashes_per_million_bike_km") %in% names(r)))
  # the protected lane was installed in 2021: all three years count -> ~1 km * 3
  p <- r[r$facility_type == "protected_lane", ]
  expect_equal(unique(round(p$km_years, 2)), 3)
  expect_equal(sum(p$n_crashes), 3L)
  expect_setequal(p$location_type, c("intersection", "mid_block", "unknown"))
  expect_equal(p$n_serious_fatal[p$location_type == "intersection"], 1L)
  # painted lane: 2 crashes, both mid-block, one fatal
  l <- r[r$facility_type == "painted_lane", ]
  expect_equal(l$location_type, "mid_block")
  expect_equal(l$n_crashes, 2L)
  expect_equal(l$n_serious_fatal, 1L)
  expect_equal(l$crashes_per_km_year, 2 / l$km_years)
  # the far crash lands on "none" with no denominator
  n <- r[r$facility_type == "none", ]
  expect_equal(nrow(n), 1L)
  expect_true(is.na(n$crashes_per_km_year))
  # exposure: protected lane carries 10x the riders, so its per-bike-km rate is lower than its per-km-year rate implies
  expect_true(all(is.finite(p$crashes_per_million_bike_km)))
  expect_equal(attr(r, "years"), 2022:2024)

  # install_year after the window start shortens the km-years
  la <- lanes_two(); la$install_year <- c(2023L, NA)
  r2 <- cl_crash_rates(cl_crash_join(la, crashes_pts()), years = 2022:2024)
  expect_equal(unique(round(r2$km_years[r2$facility_type == "protected_lane"], 2)), 2)

  # years inferred from the crashes
  r3 <- cl_crash_rates(j)
  expect_equal(attr(r3, "years"), 2022:2024)
})

test_that("cl_crash_join and cl_crash_rates validate and handle empties", {
  expect_error(cl_crash_join(data.frame(), crashes_pts()), "must be an sf")
  expect_error(cl_crash_join(lanes_two(), crashes_pts(), tolerance = 0), "positive")
  expect_error(cl_crash_rates(list()), "cl_crash_join")
  e <- cl_crash_join(lanes_two(), crashes_pts()[0, ])
  expect_equal(nrow(e$crashes), 0L)
  expect_equal(e$facilities$n_crashes, c(0L, 0L))
  skip_if_not_installed("ggplot2")
  p <- cl_plot(lanes_two(), crashes = crashes_pts())
  expect_s3_class(p, "ggplot")
})
