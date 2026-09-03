test_that("Denver is registered and its crosswalk covers every published class", {
  s <- cl_sources()
  expect_true("denver" %in% s$city)
  expect_equal(s$type[s$city == "denver"], "arcgis")

  # FACILITY_TYPE_EXISTING distinct values observed on the live service
  # (Denver_Bicycle_Facilities_ODC layer 450), 2026-09-02
  observed <- c("Trail", "Bike Lane", "Shared Sidewalk", "Buffered Bike Lane",
                "Neighborhood Bikeway", "Protected Bike Lane", "Car-Free Street",
                "Shared Street")
  cw <- cyclelanes:::.denver_crosswalk
  expect_setequal(names(cw), observed)
  expect_true(all(cw %in% cl_facility_levels()))
})

test_that("crosswalk maps known classes and warns on unknown ones", {
  cw <- c("A" = "painted_lane", "B" = "protected_lane")
  expect_equal(cyclelanes:::.apply_crosswalk(c("A", "B", NA), cw),
               c("painted_lane", "protected_lane", "none"), ignore_attr = TRUE)
  expect_warning(
    out <- cyclelanes:::.apply_crosswalk(c("A", "Zed"), cw, city = "test"),
    "Zed"
  )
  expect_equal(out, c("painted_lane", "none"), ignore_attr = TRUE)
  expect_equal(attr(out, "unmapped"), "Zed")
})

test_that("cl_register_source validates and cl_sources reports it", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))

  expect_error(cl_register_source("x", "u", "f", crosswalk = c("A" = "banana")), "not in cl_facility_levels")
  expect_error(cl_register_source("x", "u", "f", crosswalk = c("painted_lane")), "named")
  expect_error(cl_register_source("x", "u", "f", crosswalk = c(A = "painted_lane"),
                                  existing_filter = "no"), "function")

  cl_register_source("Testville", url = "nowhere.geojson", class_field = "CLS",
                     crosswalk = c(A = "painted_lane"), type = "file",
                     label = "Testville, USA", homepage = "https://example.org")
  s <- cl_sources()
  expect_true("testville" %in% s$city)
  expect_equal(s$label[s$city == "testville"], "Testville, USA")
  expect_true("denver" %in% s$city)
})

test_that("a registered source overrides a built-in of the same name", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  cl_register_source("denver", url = "local.geojson", class_field = "CLS",
                     crosswalk = c(A = "painted_lane"), type = "file", label = "Override")
  expect_equal(cl_sources()$label[cl_sources()$city == "denver"], "Override")
  expect_equal(sum(cl_sources()$city == "denver"), 1L)
})

test_that("unknown city errors with the list of known keys", {
  expect_error(cl_fetch_official("atlantis"), "denver")
})

test_that("a file source is read, filtered, and standardised", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  raw <- sf::st_sf(
    FID = 1:4,
    STREET = c("A St", "B St", "C St", "D St"),
    CLS = c("Protected", "Lane", "Mystery", NA),
    STATUS = c("Existing", "Existing", "Existing", "Planned"),
    COMFORT = c("H", "M", "L", "L"),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(-105, 39.70), c(-104.999, 39.70))),
      sf::st_linestring(rbind(c(-105, 39.71), c(-104.999, 39.71))),
      sf::st_linestring(rbind(c(-105, 39.72), c(-104.999, 39.72))),
      sf::st_linestring(rbind(c(-105, 39.73), c(-104.999, 39.73))),
      crs = 4326
    )
  )
  path <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(raw, path, quiet = TRUE)

  cl_register_source(
    "filetown", url = path, type = "file",
    id_field = "FID", name_field = "STREET", class_field = "CLS",
    extra_fields = c(comfort = "COMFORT"),
    crosswalk = c(Protected = "protected_lane", Lane = "painted_lane"),
    existing_filter = function(d) d$STATUS == "Existing",
    attribution = "test"
  )

  expect_warning(out <- cl_fetch_official("filetown"), "Mystery")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_equal(out$source_id, c("1", "2", "3"))
  expect_equal(out$name, c("A St", "B St", "C St"))
  expect_equal(as.character(out$facility_type), c("protected_lane", "painted_lane", "none"))
  expect_equal(out$comfort, c("H", "M", "L"))
  expect_true(all(out$length_m > 80 & out$length_m < 90))
  expect_equal(attr(out, "cl_source"), "filetown")
  expect_equal(attr(out, "cl_attribution"), "test")

  all4 <- suppressWarnings(cl_fetch_official("filetown", existing_only = FALSE))
  expect_equal(nrow(all4), 4L)

  # bbox restricts to the southern two ways
  south <- suppressWarnings(cl_fetch_official("filetown", bbox = c(-105.1, 39.69, -104.9, 39.715)))
  expect_equal(south$source_id, c("1", "2"))
})

test_that("standardise errors clearly when the class field is missing", {
  raw <- sf::st_sf(OTHER = "x", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.7), c(-104.999, 39.7))), crs = 4326))
  src <- list(city = "t", class_field = "CLS", crosswalk = c(A = "none"))
  expect_error(cyclelanes:::.standardise_official(raw, src), "class field")
})

test_that("standardise handles a zero-row layer", {
  raw <- sf::st_sf(CLS = character(), geometry = sf::st_sfc(crs = 4326))
  src <- list(city = "t", class_field = "CLS", crosswalk = c(A = "none"))
  out <- cyclelanes:::.standardise_official(raw, src)
  expect_equal(nrow(out), 0L)
  expect_true("facility_type" %in% names(out))
})

test_that("Austin is registered and its crosswalk covers every published class", {
  s <- cl_sources()
  expect_true("austin" %in% s$city)
  # BICYCLE_FACILITY distinct values observed on the live service, 2026-09-03
  # (cl_check_source("austin"); "None" is not a value, it was a NULL)
  observed <- c("Bike Lane", "Bike Lane - Buffered", "Bike Lane - Climbing",
                "Bike Lane - Protected One-Way", "Bike Lane - Protected Two-Way",
                "Bike Lane - wParking", "Bridge", "Neighborhood Bikeway",
                "Shared Lane", "Sharrows", "Shoulder", "Trail - Paved",
                "Trail - Unpaved", "Wide Curb Lane", "Wide Shoulder")
  cw <- cyclelanes:::.austin_crosswalk
  expect_setequal(names(cw), observed)
  expect_true(all(cw %in% cl_facility_levels()))
  expect_equal(unname(cw["Bike Lane - Protected Two-Way"]), "protected_lane")
})
