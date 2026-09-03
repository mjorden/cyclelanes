# Build an sf of short east-west ways near Denver, one per named-vector of
# tags. Each way is `len_deg` degrees of longitude long (~85.6 m at 39.7 N).
make_ways <- function(tags, len_deg = 0.001) {
  n <- nrow(tags)
  geoms <- lapply(seq_len(n), function(i) {
    y <- 39.7 + i * 0.01
    sf::st_linestring(rbind(c(-105, y), c(-105 + len_deg, y)))
  })
  sf::st_sf(tags, geometry = sf::st_sfc(geoms, crs = 4326))
}

# ways(c(highway = "residential", cycleway = "lane"), c(highway = "cycleway"))
ways <- function(...) {
  rows <- list(...)
  df <- dplyr::bind_rows(lapply(rows, function(r) {
    as.data.frame(as.list(r), check.names = FALSE, stringsAsFactors = FALSE)
  }))
  df$osm_id <- as.character(seq_len(nrow(df)))
  make_ways(df)
}

# A single classified way, as a character facility_type
ft <- function(...) as.character(cl_classify(ways(...))$facility_type)
