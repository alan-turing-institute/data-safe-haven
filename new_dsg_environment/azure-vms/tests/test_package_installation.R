
# Initialise lists
warning_list <- c()
error_list <- c()

#' Test package with non-standard evaluation and append to the proper list
test_package <- function(p) {
  tryCatch(
    eval(parse(text = paste0("library(", p, ")"))),
    error = function(m) {
      assign("error_list", c(error_list, p), envir = .GlobalEnv)
    },
    warning = function(m) {
      assign("warning_list", c(warning_list, p), envir = .GlobalEnv)
    },
    message = function(m) {
      # do nothing, as many packages print messages upon loading
    })
}

# Read in the package list from the repo
get_package_list <- function(list_dir = "../package_lists/",
                             list_files = c("cran.list", "bioconductor.list")) {
  package_list <- c()
  for (f in list_files) {
    path <- paste0(list_dir, f)
    tmp <- scan(path, what = "", sep = "\n")
    package_list <- c(package_list, tmp)
  }
  return(package_list)
}

# Test each package
package_list <- get_package_list()
for (p in package_list) {
  test_package(p)
}

# Show results
if (0 == length(warning_list) & 0 == length(error_list)) {
  print(paste("All ", length(package_list), " package(s) OK!"))
} else {

  if (0 < length(warning_list)) {
    print("The following packages gave a warning:")
    print(paste(warning_list, sep = "\n"))
    print("All the packages above gave a warning!")
  }

  if (0 < length(error_list)) {
    print("The following packages gave an error:")
    print(paste(error_list, sep = "\n"))
    print("All the packages above gave an error!")
  }
}
