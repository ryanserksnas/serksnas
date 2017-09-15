// Make it rain!!!
// Brunch menu click
$('.dinner').hide()
$('.brunch').hide()
$('#Brunch').on('click', function (){
	$('.brunch').fadeIn();
	$('.drinks').hide();
	$('.dinner').hide();
});

// Lunch menu click
$('#Dinner').on('click', function (){
	$('.dinner').fadeIn();
	$('.brunch').hide();
	$('.drinks').hide();
});

// Dinner menu click
$('#Drinks').on('click', function (){
	$('.drinks').fadeIn();
	$('.brunch').hide();
	$('.dinner').hide();
});

// //scroll bar
// $('#menu').on('click', function)({
// 	window.scrollTo(0, 500);
// });


function scrollWin() {
	window.scrollTo(0, 740);
}

function scrollWinL() {
	window.scrollTo(0, 2500);
}

function scrollWinR() {
	window.scrollTo(0, 2500);
}

function scrollWinG() {
	window.scrollTo(0, 1500);
}
function scrollWinH() {
	window.scrollTo(0, 1);
}

// $(window).scroll(function() {
//    if ($(this).scrollTop() >= 50) { // this refers to window
//        $('header nav').addClass('navcolor');
//    }

$(window).on('scroll', function () {
	// Step 1: Google $(window).scrollTop();
	var distanceScrolled = $(window).scrollTop();

	// Step 2: Log distanceScrolled to the console to see what it holds!
	if (distanceScrolled >= 250){
		$('nav').addClass('scrolled')
	} else{
		$('nav').removeClass('scrolled')
	}
  // if distanceScrolled is greater than or equal to 542
    // Add a class to the nav to make it fixed
  // else
    // Remove the class from the nav to make it unfixed
	
});

$('button').on('click', function(){
	$('.modal').fadeIn();
	$('.modal-box').fadeIn();
});
$('.request-reservation').on('click', function(){
	$('.modal').fadeOut();
	$('.modal-box').fadeOut();
});

// 

