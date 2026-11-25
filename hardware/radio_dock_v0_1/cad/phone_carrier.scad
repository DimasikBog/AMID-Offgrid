// AMID radio dock 0.1 — parametric carrier study, millimetres.
// The default phone/powerbank are envelopes, not verified product dimensions.
// Printable carrier: openscad -D show_mockups=false -o carrier.stl phone_carrier.scad
// Fold study: openscad -D antenna_folded=true ...
$fn = 32;
phone_w = 78;
phone_h = 165;
phone_t = 11;
fit_clearance = 1.5;
wall = 3;
board_w = 27.2542;
board_h = 64.5922;
board_clearance = 2;
powerbank_w = 50;
powerbank_h = 90;
powerbank_t = 20;
rod_length = 84;
feed_gap = 6;
antenna_offset = 30;
antenna_folded = false;
show_mockups = true;

inner_w = phone_w + fit_clearance * 2;
inner_h = phone_h + fit_clearance * 2;
outer_w = inner_w + wall * 2;
outer_h = inner_h + wall * 2;

assert(phone_w >= 60 && phone_h >= 140 && phone_t > 0);
assert(board_w + board_clearance * 2 < inner_w);
assert(powerbank_w + 4 < inner_w);
assert(board_h + powerbank_h + 6 < inner_h);

module slab(w,h,t,r=5) {
  linear_extrude(t) hull() for (x=[-w/2+r,w/2-r], y=[-h/2+r,h/2-r])
    translate([x,y]) circle(r=r);
}
module carrier() {
  difference() {
    union() {
      slab(outer_w,outer_h,wall);
      // Four corner retainers; the centre of each phone edge stays accessible.
      for (sx=[-1,1],sy=[-1,1]) translate([sx*(outer_w/2-5),sy*(outer_h/2-16),wall])
        cube([10,32,phone_t+3],center=true);
      // Side grips join the plate; facets are deliberate, not RF elements.
      for (sx=[-1,1]) translate([sx*(outer_w/2+5),0,wall/2])
        rotate([0,0,sx*3]) slab(16,82,wall+6,4);
      // Dielectric antenna support extends clear of the phone envelope.
      translate([-5,outer_h/2-5,0]) cube([10,antenna_offset+10,wall]);
      translate([0,outer_h/2+antenna_offset,0]) cylinder(h=wall+5,r=10);
    }
    // Phone insertion pocket; retainers intentionally do not clamp glass.
    translate([0,0,wall+.1]) slab(inner_w,inner_h,phone_t+14,4);
    // Retention straps, separate from PCB traces / mounting-hole assumptions.
    for (y=[-58,-20,28,65],x=[-inner_w/2+5,inner_w/2-5])
      translate([x,y,-1]) cube([3,12,wall+3],center=true);
    // Open-back windows and hollow grips reduce printed mass and retain air gaps.
    for (p=[[0,-47,18,38],[0,34,34,64]]) translate([p[0],p[1],-8]) slab(p[2],p[3],wall+18,3);
    for (sx=[-1,1]) translate([sx*(outer_w/2+5),0,-8]) slab(7,62,wall+24,3);
    // Cable/antenna holes are generous pass-throughs, not connector fixtures.
    translate([0,-outer_h/2+8,-1]) cube([16,10,wall+4],center=true);
    translate([0,outer_h/2+antenna_offset,-1]) cylinder(h=wall+10,d=3.4);
  }
}
module rod(side) {
  angle = antenna_folded ? (side < 0 ? 90 : -90) : 0;
  translate([side*feed_gap/2,outer_h/2+antenna_offset,wall+8]) rotate([0,0,angle])
    rotate([0,side*90,0]) cylinder(h=rod_length,d=2);
}
color([.11,.14,.16]) carrier();
if (show_mockups) {
  // Previews only: excluded from printable carrier export.
  color([.12,.32,.40,.55]) translate([0,0,wall+1]) slab(phone_w,phone_h,phone_t,5);
  color([.0,.55,.43]) translate([-board_w/2,-inner_h/2+4,-3]) cube([board_w,board_h,2]);
  color([.26,.27,.29]) translate([-powerbank_w/2,inner_h/2-powerbank_h-3,-powerbank_t]) cube([powerbank_w,powerbank_h,powerbank_t]);
  color([.96,.50,.17]) { rod(-1); rod(1); }
  color([.05,.75,.64]) translate([-7,outer_h/2+antenna_offset-6,wall+4]) cube([14,12,4]);
}
