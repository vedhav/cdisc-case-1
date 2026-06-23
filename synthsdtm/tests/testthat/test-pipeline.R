# End-to-end: build spec (offline) -> simulate -> check, on the bundled configs.

run_pipeline <- function(cfg_name, n, seed) {
  cfg <- system.file("configs", cfg_name, package = "synthsdtm")
  expect_true(file.exists(cfg))
  built <- build_spec(cfg)
  res <- simulate_sdtm(cfg, built$spec, built$ct_cache, n_subjects = n, seed = seed)
  dir <- withr::local_tempdir()
  write_sdtm(res, dir)
  rep <- check_sdtm(cfg, built$spec, built$ct_cache, run_dir = dir, n_subjects = n, seed = seed)
  list(res = res, rep = rep)
}

test_that("reference NCT04556760 has the expected (seed-independent) shape", {
  out <- run_pipeline("NCT04556760.json", 40, 1234)
  s <- out$res$summary
  expect_equal(s$DM, 40)
  expect_equal(s$IE, 2)
  expect_equal(s$VS, 720)
  expect_equal(s$EG, 640)
  expect_equal(s$LB, 2080)
  expect_equal(s$EX, 80)   # crossover => N x 2 periods
  expect_equal(s$DS, 40)
})

test_that("reference NCT04556760 passes all T1/T2/T3 checks", {
  out <- run_pipeline("NCT04556760.json", 40, 1234)
  expect_true(out$rep$allPass)
  expect_equal(out$rep$byTier$T1$failed, 0)
  expect_equal(out$rep$byTier$T2$failed, 0)
  expect_equal(out$rep$byTier$T3$failed, 0)
})

test_that("parallel toy study scales linearly and passes", {
  out <- run_pipeline("toy_parallel.json", 20, 7)
  expect_equal(out$res$summary$DM, 20)
  expect_equal(out$res$summary$EX, 20)  # parallel => 1 period
  expect_equal(out$res$summary$VS, 120) # 20 x 2 tests x 3 visits
  expect_true(out$rep$allPass)
})

test_that("generation is deterministic for a fixed seed", {
  cfg <- system.file("configs", "toy_parallel.json", package = "synthsdtm")
  b <- build_spec(cfg)
  r1 <- simulate_sdtm(cfg, b$spec, b$ct_cache, n_subjects = 20, seed = 7)
  r2 <- simulate_sdtm(cfg, b$spec, b$ct_cache, n_subjects = 20, seed = 7)
  expect_equal(r1$domains, r2$domains)
})
