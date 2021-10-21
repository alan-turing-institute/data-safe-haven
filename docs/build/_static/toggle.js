// Toggle the 'shift-up' class when rst-versions objects are clicked
$(document).on("click", "[data-toggle='rst-versions']", function () {
  $("[data-toggle='rst-versions']").toggleClass("shift-up");
});
