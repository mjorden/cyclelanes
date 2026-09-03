# Add reported bicycle crashes to the `denver_lodo` dataset without
# re-fetching the OSM and official layers. Run from the package root:
#
#   Rscript data-raw/denver_lodo_crashes.R

devtools::load_all(".", quiet = TRUE)
load("data/denver_lodo.rda")

box <- denver_lodo$bbox
crashes <- cl_fetch_crashes("denver", years = 2019:2025,
                            bbox = c(box[["xmin"]], box[["ymin"]], box[["xmax"]], box[["ymax"]]))
for (a in c("cl_fetched")) attr(crashes, a) <- NULL
sf::st_geometry(crashes) <- sf::st_set_precision(sf::st_geometry(crashes), 1e6)
rownames(crashes) <- NULL

denver_lodo$crashes <- crashes
denver_lodo$crash_years <- 2019:2025
denver_lodo$crashes_fetched <- as.Date(Sys.time())
cat(sprintf("crashes: %d bicycle crashes 2019-2025 in the box; %d serious or fatal\n",
            nrow(crashes), sum(crashes$severity %in% c("serious", "fatal"))))
save(denver_lodo, file = "data/denver_lodo.rda", compress = "xz", version = 2)
cat(sprintf("data/denver_lodo.rda: %.0f kB\n", file.info("data/denver_lodo.rda")$size / 1024))
