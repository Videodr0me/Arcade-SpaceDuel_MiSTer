//============================================================================
//  Generic pause handling for MiSTer cores.
//
//  https://github.com/JimmyStones/Pause_MiSTer
//
//  Copyright (c) 2021 Jim Gregory
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
/*
 Features:
  - Pause can be triggered by user input, hiscore module or OSD opening (optionally controlled by setting in OSD)
  - When paused the RGB outputs will be halved after 60 seconds to reduce burn-in (optionally controlled by setting in OSD)
  - Reset signal will cancel user triggered pause

 Version history:
 0001 - 2021-03-15 -	First marked release
 0002 - 2021-08-28 -	Add optional output of dim_video signal (currently used by Galaga)
============================================================================
*/
module pause #(
	parameter						RW=8,						// Width of red channel
	parameter						GW=8,						// Width of green channel
	parameter						BW=8,						// Width of blue channel
	parameter						CLK_HZ = 12_096_000		// Main clock in Hz
)
(
	input								clk_sys,					// Core system clock (should match HPS module)
	input								reset,					// CPU reset signal (active-high)
	input								user_button,			// User pause button signal (active-high)
	input								pause_request,			// Pause requested by other code (active-high)
	input [1:0]						options,					// Pause options from OSD
																	//   [0] = pause in OSD (active-high)
																	//   [1] = dim video (active-high)
	input 							OSD_STATUS,				// OSD is open (active-high)
	input	[(RW-1):0]				r,							// Red channel
	input	[(GW-1):0]				g,							// Green channel
	input	[(BW-1):0]				b,							// Blue channel

	output							pause_cpu,				// Pause signal to CPU (active-high)
	output reg                     dim_video = 1'b0,       // Source-clock dim request
	output [(RW+GW+BW-1):0]		rgb_out					// RGB output to arcade_video module

);

// Option constants
localparam 		pause_in_osd	= 1'b0;
localparam 		dim_video_timer= 1'b1;

reg				pause_toggle	= 1'b0;					// User paused (active-high)
reg [31:0]		pause_timer		= 32'd0;				// Time since pause
localparam [31:0] dim_timeout = CLK_HZ * 32'd60;
reg				user_button_last = 1'b0;

assign pause_cpu = (pause_request | pause_toggle  | (OSD_STATUS & options[pause_in_osd])) & !reset;

always @(posedge clk_sys) begin

	// Track user pause button down
	user_button_last <= user_button;
	if(!user_button_last & user_button) pause_toggle <= ~pause_toggle;

	// Clear user pause on reset
	if(pause_toggle & reset) pause_toggle <= 0;

	if(pause_cpu & options[dim_video_timer])
	begin
		// Assert on the same edge that the timer reaches the 60-second limit.
		dim_video <= (pause_timer >= dim_timeout - 32'd1);
		// Track pause duration for video dim
		if((pause_timer<dim_timeout))
		begin
			pause_timer <= pause_timer + 1'b1;
		end
	end
	else
	begin
		pause_timer <= 32'd0;
		dim_video <= 1'b0;
	end
end

assign rgb_out = dim_video ? {r >> 1,g >> 1, b >> 1} : {r,g,b};

endmodule
