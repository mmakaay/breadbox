# Ben Eater tutorial: Interrupt handling

Tutorial : https://www.youtube.com/watch?v=oOYA-jsWTmc \
Result   : https://www.youtube.com/watch?v=oOYA-jsWTmc&t=1276

I implemented the debounce countdown different from how Ben did it in the video.
I moved the debounce countdown outside the interrupt subroutine, but have it set
and checked from inside the interrupt subroutine. This has some advantages over
handling the full countdown in the IRQ handler:

 - As was mentioned in the tutorial, having the countdown in the handler
   makes the button presses feel laggy, because the LCD display is only
   updated after the debounce has completed. In this implementation, the
   IRQ handler quickly returns after starting the debounce countdown,
   allowing for immediate feedback to the user, while the deboucing is
   running in the background.

 - Starting the debounce countdown can also be seen as a signal that
   the interrupt counter value has changed. Only when a new countdown
   is started, the display is updated with the new value. This saves a lot
   of resources, compared to continuously updating the LCD, even when there
   is no new counter value to display.

A nice extra this implement adds, is a "debounce" text on the display, during
the time that debouncing is active. This gives a good insight in the
debouncing process.
