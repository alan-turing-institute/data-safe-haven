// Toggle the 'shift-up' class when rst-versions objects are clicked
$(document).on("click", "[data-toggle='rst-versions']", function () {
  $("[data-toggle='rst-versions']").toggleClass("shift-up");
});
$(document).on("click", "[data-toggle='rst-downloads']", function () {
  $("[data-toggle='rst-downloads']").toggleClass("shift-up");
});
