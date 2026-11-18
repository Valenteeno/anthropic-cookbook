// Fibonacci Pro 1.64 -- custom drawing indicator for MetaTrader 5.
// No trading functions, DLLs, network access or external fonts/assets.
// Install in MQL5/Indicators, compile with the current MetaEditor 5.
#property copyright "Custom implementation for the user"
#property version   "1.64"
#property description "Fibonacci drawings, horizontal lines, drawings list, and ICT sessions, killzones & macros with alerts."
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#include <Canvas\Canvas.mqh>

input string InpWorkspace="Main";     // Unique name for this chart instance
input string InpStorageKey="";        // Optional stable key across recreated charts
input bool   InpSnapOHLC=true;         // Magnet near OHLC; otherwise anchor freely
input int    InpSnapRadiusPixels=5;   // OHLC magnet radius in chart pixels (0..80)
input int    InpLineSnapPixels=20;    // Single-click horizontal line: OHLC magnet radius (0..80)
input int    InpFrameMilliseconds=8;   // Requested redraw interval (8..100 ms)
input double InpUIScale=1.0;           // Panel scaling (0.75..2.0)
input color  InpDefaultColor=clrDarkOrange;
input int    InpMaximumSetups=1000;    // 1..1000 drawings per workspace
input bool   InpHoverCandleInfo=true;  // Hover a candle to show its OHLC
input bool   InpHoverFibInfo=true;     // Hover a Fib level to show its details
input string InpPanelHotkey="Ctrl+Shift+H";     // Hide/show the full tool interface
input string InpDuplicateHotkey="Ctrl+Shift+D"; // Duplicate highlighted custom Fib
input string InpZonesHotkey="Ctrl+Shift+K";     // Show/hide sessions, killzones & macros

#define FP_TOOLBAR_WIDTH 466
#define FP_TOOLBAR_HEIGHT 49
#define FP_PANEL_WIDTH 488
#define FP_LIST_WIDTH 520
#define FP_VERSION "1.64"
#define FP_FAR_FUTURE 32503680000
#define FP_MAX_SETUPS 1000
#define FP_MAX_LEVELS 64
#define FP_TF_COUNT 21
#define FP_ALL_TF_MASK 2097151
#define FP_MAGIC 1179668785
#define FP_END 1179668799
#define FP_SCHEMA 1
#define FP_PRESET_MAGIC 1179668801
#define FP_PRESET_END 1179668809
#define FP_LAYOUT_MAGIC 1179668811
#define FP_OFF -2147483000
#define FP_REG_MAX 768
#define FP_BEAT_MS 400
#define FP_STALE_MS 1500
#define FP_DUPLICATE_MS 5000
#define FP_STATUS_MS 5000
#define FP_TIP_IDLE_MS 10000
#define FP_DEFAULT_TEXT "%%  (%$)"

struct FPLevel
  {
   bool enabled;
   double value;                  // 0.0 = 0%, 1.0 = 100%
   string description;            // %$ expands to price, %% to percentage
   int style;                     // ENUM_LINE_STYLE 0..4
   int width;
   color ink;
  };
struct FPSetup
  {
   int uid;
   string name;
   string description;
   datetime ta,tb;                 // Analytical anchors; never edited by drawers
   double pa,pb;
   datetime left,right;            // Independent horizontal display boundaries
   ENUM_TIMEFRAMES source_tf;      // Immutable drawing timeframe
   long visible_mask;              // One bit per timeframe; higher timeframes allowed
   int visibility_mode;            // 0 custom subset, 1 source and lower, 2 source only
   bool ray_left,ray_right;
   bool anchors_locked;
   bool diagonal,labels;
   int label_v;                    // 0 above the level, 1 below the level
   int label_h;                    // 0 at the origin (left), 1 at the end (right)
   bool label_float;               // Keep labels inside the window / at the window edge when rayed
   bool hline;                     // Single-level horizontal line moved by its origin handle
   color base_color;
   bool fill,gradient,fill_rays;
   color fill_top,fill_bottom;
   int opacity;
   int count;
   FPLevel levels[FP_MAX_LEVELS];
  };
// Screen projection of one drawing, rebuilt once per rendered frame and reused by
// hit-testing and hover so the chart projection API is not queried per mouse event.
struct FPGeo
  {
   bool valid;
   int xa,ya,xb,yb,xl,xr,l,r;
   int count,line;
   int ly[FP_MAX_LEVELS];
  };
// Registry of the native UI objects this instance owns. It replaces synchronous
// ObjectFind/ObjectGet* calls and lets rebuilds send only properties that changed.
struct FPObj
  {
   string name;
   int type,x,y,w,h,z,fs,bg,fg,gen;
   string text;
   bool textset;
  };

#define FPZ_MAX 64
#define FPZ_GROUPS 5
#define FPZ_MAGIC 1179668821
#define FPZ_END 1179668829
#define FPZ_SCHEMA 2
#define FPZ_PANEL_WIDTH 560
#define FPZ_BUILTIN_FX "ICT Forex [built-in]"
#define FPZ_BUILTIN_IDX "ICT Indices [built-in]"
// One session, killzone, macro or time line. Times are minutes after midnight, New York.
struct FPZone
  {
   bool enabled;
   string name;
   int start,end;              // start==end draws a single time line; end<start runs past midnight
   int style;                  // 0..4 line styles, 5 = no boundary lines
   int width;
   color ink;
   int label;                  // 0 off, 1 name, 2 name + times
   int marker;                 // 0 off, 1 below the low, 2 above the high, 3 chart bottom, 4 chart top
   int align;                  // 0 centre, 1 right
   int distance;               // marker gap to the zone's low/high, or to the chart edge, pixels
   int height;                 // marker strip height, pixels
   int mopacity;               // marker shade opacity 0..100
   int group;                  // 0 session, 1 killzone, 2 silver bullet, 3 macro, 4 time line
   bool fill,box,extend,alert;
   int open_line;              // 0 off, 1 to the zone end, 2 to the end of the trading day
   bool midline;               // 50% line of the zone's range
   int stack;                  // marker placement: 0 auto (steps clear of overlapping strips), 1 fixed at `distance`
  };
struct FPZoneConfig
  {
   bool enabled;
   bool group_on[FPZ_GROUPS];
   int group_tf[FPZ_GROUPS];   // highest timeframe index each group is drawn on
   int days_back;
   bool upcoming;
   int dow_mask;               // trading-day weekdays shown, bit 0 = Sunday
   int broker_mode;            // 0 auto, 1 NY+7, 2 GMT+N fixed, 3 GMT+N with EU DST, 4 GMT+N with US DST
   int broker_gmt;             // N in hours (the winter offset for the DST modes)
   bool fill;
   int fill_mode;              // 0 full height, 1 range box, 2 both
   int opacity;
   bool gradient,fade_old,lines_full,declutter,highlight,hover;
   int label_size;             // pixels
   bool alert_sound,alert_push;
   int alert_lead;             // minutes before the start
   int cut;                    // zones cut through Fib shading: 0 off, 1 half, 2 clear
   int fib_lower;              // Fib shading on charts below its own timeframe: 0 full, 1 faint, 2 off
   int count;
   FPZone zones[FPZ_MAX];
  };
// One drawn instance of a zone on a given trading day.
struct FPZoneOcc
  {
   int zone,day,age,state;     // state: 0 unread, 1 has data, 2 no bars (holiday), 3 history loading
   datetime ny,ts,te;          // NY wall-clock start; server-time start and end
   bool live,future;
   double hi,lo,op;
   datetime done_to,hi_taken,lo_taken,scan_to;
  };
struct FPZoneVis
  {int occ,x0,x1,yh,yl,yo,xh,xl,xe;};   // xh/xl: ends of the extended high/low, xe: end of the opening line
// A translucent rectangle to composite. ink/ink2: top and bottom colour (equal when flat),
// a0/a1: top and bottom opacity. kind 0: zone shading or strip, 1: Fib fill.
struct FPLayer
  {int x0,x1,y0,y1;color ink,ink2;double a0,a1;int kind;};
// A composited cell: argb on its top row, argb1 on its bottom row (equal when flat).
struct FPSeg
  {int x0,x1,y0,y1;uint argb,argb1;};
// Marker/label strip of one visible zone: its own rectangle, never shared with another zone.
struct FPMark
  {
   int vis,anchor,x0,x1,y0,y1,tw,start;
   long ts,te;
   double alpha;
   bool shade,fixed;
   string text;
  };

// PURE_GEOMETRY_BEGIN -- compiled directly by the included local test harness.
double FPLevelPrice(const double pa,const double pb,const double ratio)
  { return pb+ratio*(pa-pb); }
// Source timeframe and every lower timeframe: the default visibility set.
long FPAllowedMask(const int source_index)
  { return (source_index<0 || source_index>20)?0:(((long)1<<(source_index+1))-1); }
long FPAdaptMask(const long mask,const int source_index,const int target_index,const int mode=-1)
  {
   if(source_index<0 || target_index<0)return 0;
   long allowed=FPAllowedMask(target_index),source_allowed=FPAllowedMask(source_index),own=(long)1<<target_index;
   if(mode==1)return allowed;
   if(mode==2)return own;
   // A drawing must always be visible on the timeframe it is drawn on.
   if(mode==0)return (mask&FP_ALL_TF_MASK)|own;
   if(mask==source_allowed)return allowed;
   if(mask==((long)1<<source_index))return own;
   return (mask&FP_ALL_TF_MASK)|own;
  }
bool FPShortcutMatch(const int key,const int wanted,const bool ctrl,const bool shift,const bool alt,const bool want_ctrl,const bool want_shift,const bool want_alt)
  {return key==wanted && ctrl==want_ctrl && shift==want_shift && alt==want_alt;}
void FPSetExtent(datetime &left,datetime &right,const datetime value,const bool is_left)
  {
   if(is_left) left=(value<right)?value:right-1;
   else right=(value>left)?value:left+1;
  }
int FPPatternLength(const int style,const int part,const int width)
  {
   int dot=(width>1)?width:1;
   if(style==1) return (part%2==0)?8:5;
   if(style==2) return (part%2==0)?dot:4;
   if(style==3) { int p=part%4; return p==0?8:(p==2?dot:4); }
   if(style==4) { int p=part%6; return p==0?8:((p==2 || p==4)?dot:4); }
   return 1;
  }
color FPHSV(double hue,double sat,double val)
  {
   hue=hue-360.0*MathFloor(hue/360.0);
   double chroma=val*sat,section=hue/60.0;
   double x=chroma*(1.0-MathAbs(MathMod(section,2.0)-1.0));
   double r=0,g=0,b=0,m=val-chroma;
   int sector=(int)MathFloor(section);
   if(sector==0){r=chroma;g=x;} else if(sector==1){r=x;g=chroma;}
   else if(sector==2){g=chroma;b=x;} else if(sector==3){g=x;b=chroma;}
   else if(sector==4){r=x;b=chroma;} else {r=chroma;b=x;}
   return (color)((int)MathRound((r+m)*255.0)|((int)MathRound((g+m)*255.0)<<8)|((int)MathRound((b+m)*255.0)<<16));
  }
color FPBlend(const color top,const color bottom,const double fraction)
  {
   int result=0;
   for(int shift=0;shift<=16;shift+=8)
     {
      int a=((int)top>>shift)&255,b=((int)bottom>>shift)&255;
      result|=((int)MathRound(a+(b-a)*fraction))<<shift;
     }
   return (color)result;
  }
// Liang-Barsky clip; avoids enormous raster work on distant/off-screen anchors.
bool FPClip(double &x0,double &y0,double &x1,double &y1,const int w,const int h)
  {
   double dx=x1-x0,dy=y1-y0,u0=0.0,u1=1.0;
   double p[4],q[4];
   p[0]=-dx;p[1]=dx;p[2]=-dy;p[3]=dy;
   q[0]=x0;q[1]=w-1-x0;q[2]=y0;q[3]=h-1-y0;
   for(int i=0;i<4;i++)
     {
      if(MathAbs(p[i])<1e-12) {if(q[i]<0) return false;continue;}
      double r=q[i]/p[i];
      if(p[i]<0){if(r>u1)return false;if(r>u0)u0=r;}
      else {if(r<u0)return false;if(r<u1)u1=r;}
     }
   x1=x0+u1*dx;y1=y0+u1*dy;x0=x0+u0*dx;y0=y0+u0*dy;
   return true;
  }
// Left x of a level label. side 0 = origin (left extent), 1 = end (right extent).
// Floating labels stay inside the visible part of the level, and sit at the window
// edge when the level is rayed in that direction; fixed labels move with the Fib.
int FPLabelX(const int xl,const int xr,const int l,const int r,const int tw,const int width,const int side,const bool ray_left,const bool ray_right,const bool floating,const int pad)
  {
   int x=(side==1)?(((floating && ray_right)?width-1:xr)-pad-tw):(((floating && ray_left)?0:xl)+pad);
   if(!floating)return x;
   int lo=((l>0)?l:0)+pad,hi=((r<width-1)?r:width-1)-pad-tw;
   if(hi<lo)hi=lo;
   if(x<lo)x=lo;
   if(x>hi)x=hi;
   if(x>width-tw-2)x=width-tw-2;
   if(x<2)x=2;
   return x;
  }
ulong FPMix(ulong hash,const long value)
  {hash^=(ulong)value;hash*=(ulong)1099511628211;return hash;}
// PURE_GEOMETRY_END

FPSetup g_sets[FP_MAX_SETUPS],g_stage[FP_MAX_SETUPS],g_edit,g_drag_backup,g_last_config;
FPGeo g_geo[FP_MAX_SETUPS];
bool g_need_redraw=false,g_cull_ok=false,g_old_wheel=true;
datetime g_vt0=0,g_vt1=0;
int g_save_gen=0;
string g_version=FP_VERSION;
FPObj g_reg[FP_REG_MAX];
int g_reg_count=0,g_reg_hint=0,g_gen=0;
bool g_has_last_config=false,g_edit_error=false,g_last_config_persisted=false;
int g_count=0,g_next_uid=1,g_selected=-1,g_tab=2,g_page=0,g_rows=9;
bool g_editor=false,g_hidden=false,g_armed=false,g_dirty=true,g_ui_dirty=true;
bool g_prev_down=false,g_scroll_held=false,g_scroll_before=true,g_old_mouse=false;
int g_drag=0,g_created=-1,g_previous_selection=-1,g_drag_x=0,g_drag_y=0;
datetime g_drag_time=0;double g_drag_price=0;
int g_width=0,g_height=0,g_panel_x=16,g_panel_y=62;
double g_scale=1.0;
bool g_detaching=false;
string g_shortname,g_pending_name;
string g_prefix,g_ws_prefix,g_alive,g_token;
string g_store,g_last_store,g_layout_store,g_status="New Fib: press, drag and release.";
bool g_owner=false,g_dup_reported=false,g_wait_reported=false;
ulong g_wait_since=0,g_wait_last=0,g_last_beat=0,g_last_house=0;
CCanvas g_fill_canvas,g_line_canvas,g_picker,g_tip;
bool g_canvas_ready=false,g_picker_ready=false;
ulong g_fill_sig=0;
ulong g_ui_defer_until=0,g_render_retry_after=0;
bool g_primary_valid=false,g_view_probe=true;
int g_file_lock=INVALID_HANDLE;
int g_popup=0,g_popup_row=-1,g_popup_x=0,g_popup_y=0,g_popup_w=0,g_popup_h=0,g_popup_items=0; // 1 style, 2 width, 3 palette, 4 presets, 5..7 label position
int g_picker_target=-1; // >=0 level; -2 top fill; -3 bottom fill; -4 base/diagonal; -5 every level
color g_pick_color=clrRoyalBlue;
double g_hue=225,g_saturation=.7,g_value=.9;
int g_picker_drag=0;
ulong g_last_view=0,g_last_down=0;
ulong g_last_frame=0,g_fast_view_until=0;
int g_last_hit=-1;
long g_view_first=-1,g_view_scale=-1,g_view_bars=-1;
double g_view_min=0,g_view_max=0;
datetime g_view_time=0;
double g_toolbar_lx=10,g_toolbar_ly=8;
int g_toolbar_x=10,g_toolbar_y=8,g_toolbar_dx=0,g_toolbar_dy=0;
bool g_toolbar_drag=false,g_toolbar_moved=false;
ulong g_ignore_toolbar_click_until=0;
int g_panel_key=72,g_duplicate_key=68;
bool g_panel_ctrl=true,g_panel_shift=true,g_panel_alt=false;
bool g_duplicate_ctrl=true,g_duplicate_shift=true,g_duplicate_alt=false;
bool g_panel_key_held=false,g_duplicate_key_held=false;
string g_preset_names[256],g_preset_name="Default";
int g_preset_count=0,g_preset_page=0;
bool g_preset_save=false;
string g_delete_confirm="";ulong g_delete_confirm_until=0;
int g_tf=-1,g_frame_ms=16;
color g_chart_fg=clrBlack,g_chart_bg=clrWhite;
ulong g_status_until=0;bool g_status_dirty=false,g_status_shown=false;
// Opacity slider (Fill tab)
bool g_slider_on=false,g_slider_drag=false;
int g_slider_x0=0,g_slider_x1=0,g_slider_y0=0,g_slider_y1=0;
// Hover information
int g_mouse_x=-1,g_mouse_y=-1;bool g_mouse_in=false,g_hover_pending=false;ulong g_last_mouse=0;
bool g_tip_ready=false,g_tip_visible=false;string g_tip_key="";
int g_tip_x=FP_OFF,g_tip_y=FP_OFF,g_tip_w=0,g_tip_h=0,g_tip_cw=0,g_tip_ch=0;
// Drawings list
bool g_list=false,g_list_desc=true,g_list_follow=false;
int g_list_page=0,g_list_rows=12,g_list_filter=0,g_list_sort=0,g_list_n=0,g_list_hover=-1,g_list_confirm=-1,g_list_last_slot=-1;
ulong g_list_confirm_until=0,g_list_last_click=0;
string g_list_search="",g_list_key="";
int g_list_idx[FP_MAX_SETUPS],g_list_rowslot[16];
// Sessions, killzones & macros
FPZoneConfig g_zcfg,g_zedit,g_zact;
bool g_zeditor=false,g_zocc_dirty=true,g_zlive_on=false,g_preset_zones=false,g_zones_key_held=false;
int g_ztab=3,g_zpage=0,g_zfilter=-1,g_zmode=1,g_zgmt=2,g_zocc_n=0,g_zocc_daykey=0,g_zvis_n=0,g_zfill_n=0,g_zmark_n=0;
int g_zones_key=75;
bool g_zones_ctrl=true,g_zones_shift=true,g_zones_alt=false;
ulong g_zone_tick=0,g_zone_resolve=0,g_zone_retry=0,g_zone_poll=0,g_zfill_sig=0;
string g_zstore="",g_zbutton_tip="Sessions, killzones & macros";
datetime g_zstore_mtime=0;
color g_zlive_ink=clrWhite;
FPZoneOcc g_zocc[];
FPZoneVis g_zvis[];
FPLayer g_zfill[];
FPMark g_zmark[];
string g_dow_names[]={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
FPLayer g_shade[];
FPLayer g_shade_fib[];
int g_shade_tf[];
int g_shade_slot[];
int g_shade_ord[];
bool g_zdrag=false;
int g_zdrag_zone=-1,g_zdrag_anchor=0,g_zdrag_dy=0,g_zdrag_h=0,g_zdrag_base=0,g_zdrag_old_distance=0,g_zdrag_old_stack=0,g_zdrag_press_y=0;
bool g_zdrag_moved=false;   // a press becomes a drag after 3 px, so a plain click changes nothing

ENUM_TIMEFRAMES g_timeframes[]={PERIOD_M1,PERIOD_M2,PERIOD_M3,PERIOD_M4,PERIOD_M5,
 PERIOD_M6,PERIOD_M10,PERIOD_M12,PERIOD_M15,PERIOD_M20,PERIOD_M30,PERIOD_H1,
 PERIOD_H2,PERIOD_H3,PERIOD_H4,PERIOD_H6,PERIOD_H8,PERIOD_H12,PERIOD_D1,PERIOD_W1,PERIOD_MN1};
string g_tf_names[]={"M1","M2","M3","M4","M5","M6","M10","M12","M15","M20","M30","H1","H2","H3","H4","H6","H8","H12","D1","W1","MN1"};
string g_style_names[]={"Solid","Dash","Dot","Dash-dot","Dash-dot-dot"};
color g_palette[]={
 clrBlack,clrDarkGreen,clrDarkSlateGray,clrOlive,clrGreen,clrTeal,clrNavy,clrPurple,
 clrMaroon,clrIndigo,clrMidnightBlue,clrDarkBlue,clrDarkOliveGreen,clrSaddleBrown,clrForestGreen,clrOliveDrab,
 clrSeaGreen,clrDarkGoldenrod,clrDarkSlateBlue,clrSienna,clrMediumBlue,clrBrown,clrDarkTurquoise,clrDimGray,
 clrLightSeaGreen,clrDarkViolet,clrFireBrick,clrMediumVioletRed,clrMediumSeaGreen,clrChocolate,clrCrimson,clrSteelBlue,
 clrGoldenrod,clrMediumSpringGreen,clrLawnGreen,clrCadetBlue,clrDarkOrchid,clrYellowGreen,clrLimeGreen,clrOrangeRed,
 clrDarkOrange,clrOrange,clrGold,clrYellow,clrChartreuse,clrLime,clrSpringGreen,clrAqua,
 clrDeepSkyBlue,clrBlue,clrMagenta,clrRed,clrGray,clrSlateGray,clrPeru,clrBlueViolet,
 clrLightSlateGray,clrDeepPink,clrMediumTurquoise,clrDodgerBlue,clrTurquoise,clrRoyalBlue,clrSlateBlue,clrDarkKhaki,
 clrIndianRed,clrMediumOrchid,clrGreenYellow,clrMediumAquamarine,clrDarkSeaGreen,clrTomato,clrRosyBrown,clrOrchid,
 clrMediumPurple,clrPaleVioletRed,clrCoral,clrCornflowerBlue,clrDarkGray,clrSandyBrown,clrMediumSlateBlue,clrTan,
 clrDarkSalmon,clrBurlyWood,clrHotPink,clrSalmon,clrViolet,clrLightCoral,clrSkyBlue,clrLightSalmon,
 clrPlum,clrKhaki,clrLightGreen,clrAquamarine,clrSilver,clrLightSkyBlue,clrLightSteelBlue,clrLightBlue,
 clrPaleGreen,clrThistle,clrPowderBlue,clrPaleGoldenrod,clrPaleTurquoise,clrLightGray,clrWheat,clrNavajoWhite,
 clrMoccasin,clrLightPink,clrGainsboro,clrPeachPuff,clrPink,clrBisque,clrLightGoldenrod,clrBlanchedAlmond,
 clrLemonChiffon,clrBeige,clrAntiqueWhite,clrPapayaWhip,clrCornsilk,clrLightYellow,clrLightCyan,clrLinen,
 clrLavender,clrMistyRose,clrOldLace,clrWhiteSmoke,clrSeashell,clrIvory,clrHoneydew,clrAliceBlue,
 clrLavenderBlush,clrMintCream,clrSnow,clrWhite};
string g_color_names[]={
 "Black","DarkGreen","DarkSlateGray","Olive","Green","Teal","Navy","Purple",
 "Maroon","Indigo","MidnightBlue","DarkBlue","DarkOliveGreen","SaddleBrown","ForestGreen","OliveDrab",
 "SeaGreen","DarkGoldenrod","DarkSlateBlue","Sienna","MediumBlue","Brown","DarkTurquoise","DimGray",
 "LightSeaGreen","DarkViolet","FireBrick","MediumVioletRed","MediumSeaGreen","Chocolate","Crimson","SteelBlue",
 "Goldenrod","MediumSpringGreen","LawnGreen","CadetBlue","DarkOrchid","YellowGreen","LimeGreen","OrangeRed",
 "DarkOrange","Orange","Gold","Yellow","Chartreuse","Lime","SpringGreen","Aqua",
 "DeepSkyBlue","Blue","Magenta","Red","Gray","SlateGray","Peru","BlueViolet",
 "LightSlateGray","DeepPink","MediumTurquoise","DodgerBlue","Turquoise","RoyalBlue","SlateBlue","DarkKhaki",
 "IndianRed","MediumOrchid","GreenYellow","MediumAquamarine","DarkSeaGreen","Tomato","RosyBrown","Orchid",
 "MediumPurple","PaleVioletRed","Coral","CornflowerBlue","DarkGray","SandyBrown","MediumSlateBlue","Tan",
 "DarkSalmon","BurlyWood","HotPink","Salmon","Violet","LightCoral","SkyBlue","LightSalmon",
 "Plum","Khaki","LightGreen","Aquamarine","Silver","LightSkyBlue","LightSteelBlue","LightBlue",
 "PaleGreen","Thistle","PowderBlue","PaleGoldenrod","PaleTurquoise","LightGray","Wheat","NavajoWhite",
 "Moccasin","LightPink","Gainsboro","PeachPuff","Pink","Bisque","LightGoldenrod","BlanchedAlmond",
 "LemonChiffon","Beige","AntiqueWhite","PapayaWhip","Cornsilk","LightYellow","LightCyan","Linen",
 "Lavender","MistyRose","OldLace","WhiteSmoke","Seashell","Ivory","Honeydew","AliceBlue",
 "LavenderBlush","MintCream","Snow","White"};

int Lim(const int v,const int lo,const int hi){return (int)MathMax(lo,MathMin(hi,v));}
int U(const double pixels){return (int)MathRound(pixels*g_scale);}
int TFIndex(const ENUM_TIMEFRAMES tf)
  {for(int i=0;i<ArraySize(g_timeframes);i++)if(g_timeframes[i]==tf)return i;return -1;}
long Allowed(const ENUM_TIMEFRAMES tf){return FPAllowedMask(TFIndex(tf));}
// The chart timeframe never changes during an instance's life (MT5 reloads indicators on
// a timeframe switch), so its index is cached instead of searched on every frame.
bool Visible(FPSetup &s)
  {return g_tf>=0 && (s.visible_mask & ((long)1<<g_tf))!=0;}
int MaxSetups(){return Lim(InpMaximumSetups,1,FP_MAX_SETUPS);}
string Obj(const string tail){return g_prefix+tail;}
string UIS(const string tail){return Obj("U."+tail);}
string SafeName(string value)
  {
   string forbidden="\\/:*?\"<>|\r\n\t";
   for(int i=0;i<StringLen(forbidden);i++)StringReplace(value,StringSubstr(forbidden,i,1),"_");
   return StringSubstr(value,0,80);
  }
// Short, dot-free object-name tag: workspace "A" can never prefix workspace "A.B",
// and long names cannot push object names past MT5's 63-character limit.
string WorkspaceTag()
  {
   string tag=SafeName(InpWorkspace);
   StringReplace(tag,".","_");StringReplace(tag," ","_");
   if(StringLen(tag)==0)return "_";
   if(StringLen(tag)<=16)return tag;
   uint hash=2166136261;
   for(int i=0;i<StringLen(tag);i++){hash^=(uint)StringGetCharacter(tag,i);hash*=16777619;}
   return StringSubstr(tag,0,10)+"~"+StringFormat("%05X",hash&0xFFFFF);
  }
string MakeToken()
  {
   MathSrand((uint)(GetTickCount64()^GetMicrosecondCount()^(ulong)ChartID()));
   ulong v=GetTickCount64()*7919+GetMicrosecondCount()+((ulong)MathRand()<<16)+(ulong)MathRand();
   string digits="0123456789abcdefghijklmnopqrstuvwxyz",token="";
   for(int i=0;i<6;i++){token+=StringSubstr(digits,(int)(v%36),1);v/=36;}
   return token;
  }
string RatioText(const double value)
  {
   string text=DoubleToString(value,16);
   while(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)=="0")text=StringSubstr(text,0,StringLen(text)-1);
   if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)==".")text=StringSubstr(text,0,StringLen(text)-1);
   return text;
  }
string PercentText(const double ratio)
  {
   string text=DoubleToString(ratio*100.0,3);
   while(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)=="0")text=StringSubstr(text,0,StringLen(text)-1);
   if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)==".")text=StringSubstr(text,0,StringLen(text)-1);
   return text+"%";
  }
// Non-ASCII symbols are built from code points so the source stays plain ASCII.
string Glyph(const ushort code){return ShortToString(code);}
string Clip(const string text,const int length)
  {return StringLen(text)<=length?text:StringSubstr(text,0,length-3)+"...";}
void Status(const string value)
  {
   g_status=value;g_status_until=GetTickCount64()+FP_STATUS_MS;g_status_dirty=true;
   if(g_owner && RegFind(UIS("T.Grip"))>=0)
     {string title=g_selected>=0 && g_selected<g_count?g_sets[g_selected].name:"No selection";ObjectSetString(0,UIS("T.Grip"),OBJPROP_TOOLTIP,title+" | "+g_status+" | Drag title to move");}
  }
bool ParseHotkey(string text,int &key,bool &ctrl,bool &shift,bool &alt)
  {
   StringReplace(text," ","");StringToUpper(text);
   string tokens[];int n=StringSplit(text,'+',tokens);key=0;ctrl=false;shift=false;alt=false;
   for(int i=0;i<n;i++)
     {
      string token=tokens[i];
      if(token=="CTRL" || token=="CONTROL"){if(ctrl)return false;ctrl=true;continue;}
      if(token=="SHIFT"){if(shift)return false;shift=true;continue;}
      if(token=="ALT"){if(alt)return false;alt=true;continue;}
      if(key!=0)return false;
      if(StringLen(token)==1)
        {int c=(int)StringGetCharacter(token,0);if((c>='A' && c<='Z') || (c>='0' && c<='9'))key=c;else return false;}
      else if(StringSubstr(token,0,1)=="F")
        {int f=(int)StringToInteger(StringSubstr(token,1));if(f<1 || f>12 || token!="F"+IntegerToString(f))return false;key=111+f;}
      else return false;
     }
   return key>0;
  }
bool SameShortcut()
  {return g_panel_key==g_duplicate_key && g_panel_ctrl==g_duplicate_ctrl && g_panel_shift==g_duplicate_shift && g_panel_alt==g_duplicate_alt;}
bool ShortcutsClash()
  {
   bool pz=g_panel_key==g_zones_key && g_panel_ctrl==g_zones_ctrl && g_panel_shift==g_zones_shift && g_panel_alt==g_zones_alt;
   bool dz=g_duplicate_key==g_zones_key && g_duplicate_ctrl==g_zones_ctrl && g_duplicate_shift==g_zones_shift && g_duplicate_alt==g_zones_alt;
   return SameShortcut() || pz || dz;
  }
bool Numeric(string text)
  {
   StringTrimLeft(text);StringTrimRight(text);
   int n=StringLen(text),digits=0,dots=0;
   if(n==0)return false;
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(text,i);
      if(c>='0' && c<='9'){digits++;continue;}
      if(c=='.' && dots==0){dots++;continue;}
      if((c=='-' || c=='+') && i==0)continue;
      return false;
     }
   return digits>0;
  }
void DefaultLevel(FPLevel &level,const double value)
  {level.enabled=true;level.value=value;level.description=FP_DEFAULT_TEXT;level.style=STYLE_SOLID;level.width=1;level.ink=InpDefaultColor;}
void Defaults(FPSetup &s)
  {
   double ratios[]={0,.236,.382,.5,.618,.786,1};
   s.count=ArraySize(ratios);
   for(int i=0;i<s.count;i++)DefaultLevel(s.levels[i],ratios[i]);
  }
// CONFIG_LOGIC_BEGIN -- production functions also exercised by local tests.
void CopyConfig(FPSetup &target,FPSetup &source)
  {
   target.ray_left=source.ray_left;target.ray_right=source.ray_right;
   target.anchors_locked=source.anchors_locked;target.diagonal=source.diagonal;target.labels=source.labels;
   target.label_v=source.label_v;target.label_h=source.label_h;target.label_float=source.label_float;
   target.base_color=source.base_color;target.fill=source.fill;target.gradient=source.gradient;target.fill_rays=source.fill_rays;
   target.fill_top=source.fill_top;target.fill_bottom=source.fill_bottom;target.opacity=source.opacity;
   target.visibility_mode=source.visibility_mode;
   target.visible_mask=FPAdaptMask(source.visible_mask,TFIndex(source.source_tf),TFIndex(target.source_tf),source.visibility_mode);
   target.count=source.count;
   for(int i=0;i<target.count;i++)target.levels[i]=source.levels[i];
  }
void CopyDuplicate(FPSetup &target,FPSetup &source,const int uid)
  {
   target=source;target.uid=uid;
   target.name=StringSubstr(source.name,0,95)+" copy "+IntegerToString(uid);
  }
bool SameConfig(FPSetup &a,FPSetup &b)
  {
   if(a.ray_left!=b.ray_left || a.ray_right!=b.ray_right || a.anchors_locked!=b.anchors_locked || a.diagonal!=b.diagonal || a.labels!=b.labels || a.base_color!=b.base_color)return false;
   if(a.label_v!=b.label_v || a.label_h!=b.label_h || a.label_float!=b.label_float)return false;
   if(a.fill!=b.fill || a.gradient!=b.gradient || a.fill_rays!=b.fill_rays || a.fill_top!=b.fill_top || a.fill_bottom!=b.fill_bottom || a.opacity!=b.opacity || a.visible_mask!=b.visible_mask || a.visibility_mode!=b.visibility_mode || a.source_tf!=b.source_tf || a.count!=b.count)return false;
   for(int i=0;i<a.count;i++)
     {if(a.levels[i].enabled!=b.levels[i].enabled || a.levels[i].value!=b.levels[i].value || a.levels[i].description!=b.levels[i].description || a.levels[i].style!=b.levels[i].style || a.levels[i].width!=b.levels[i].width || a.levels[i].ink!=b.levels[i].ink)return false;}
   return true;
  }
// CONFIG_LOGIC_END
bool SamePlacement(FPSetup &a,FPSetup &b)
  {return a.ta==b.ta && a.tb==b.tb && a.pa==b.pa && a.pb==b.pb && a.left==b.left && a.right==b.right && a.ray_left==b.ray_left && a.ray_right==b.ray_right;}
void NewSetup(FPSetup &s)
  {
   s.uid=g_next_uid++;s.name="Fibo "+IntegerToString(s.uid);s.description="";
   s.ta=0;s.tb=0;s.pa=0;s.pb=0;s.left=0;s.right=0;
   s.source_tf=(ENUM_TIMEFRAMES)_Period;s.visible_mask=Allowed(s.source_tf);s.visibility_mode=1;
   s.ray_left=false;s.ray_right=false;s.anchors_locked=false;s.diagonal=true;s.labels=true;
   s.label_v=0;s.label_h=0;s.label_float=true;s.hline=false;
   s.base_color=InpDefaultColor;s.fill=false;s.gradient=false;s.fill_rays=true;
   s.fill_top=clrRoyalBlue;s.fill_bottom=clrPowderBlue;s.opacity=12;Defaults(s);
   if(g_has_last_config)CopyConfig(s,g_last_config);
  }
// Index of the level a horizontal line is drawn and moved by (first enabled level).
int LineLevel(FPSetup &s)
  {for(int i=0;i<s.count;i++)if(s.levels[i].enabled)return i;return -1;}
// A boundary level (0%, else 100%, else the lowest ratio); created when the list is empty.
int BoundaryLevel(FPSetup &s)
  {
   for(int i=0;i<s.count;i++)if(s.levels[i].value==0.0)return i;
   for(int i=0;i<s.count;i++)if(s.levels[i].value==1.0)return i;
   int best=-1;
   for(int i=0;i<s.count;i++)if(best<0 || s.levels[i].value<s.levels[best].value)best=i;
   if(best<0 && s.count<FP_MAX_LEVELS){DefaultLevel(s.levels[0],0.0);s.count=1;best=0;}
   return best;
  }
void HoldScroll()
  {if(!g_scroll_held){g_scroll_before=(bool)ChartGetInteger(0,CHART_MOUSE_SCROLL);ChartSetInteger(0,CHART_MOUSE_SCROLL,false);g_scroll_held=true;}}
void ReleaseScroll()
  {if(g_scroll_held){ChartSetInteger(0,CHART_MOUSE_SCROLL,g_scroll_before);g_scroll_held=false;}}
bool XY(const datetime t,const double p,int &x,int &y)
  {return ChartTimePriceToXY(0,0,t,p,x,y);}
bool Point(const int x,const int y,datetime &t,double &p)
  {int sub=-1;bool ok=ChartXYToTimePrice(0,x,y,sub,t,p) && sub==0 && MathIsValidNumber(p);if(ok)p=NormalizeDouble(p,_Digits);return ok;}
// One CopyRates call for the bar under the cursor and its two neighbours.
bool Snap(const int x,const int y,const ENUM_TIMEFRAMES tf,datetime &t,double &p,const int radius_pixels)
  {
   if(!Point(x,y,t,p))return false;
   if(!InpSnapOHLC)return true;
   int radius=Lim(radius_pixels,0,80);
   if(radius==0)return true;
   int shift=iBarShift(_Symbol,tf,t,false);
   if(shift<0)return true; // Missing history must not block free placement.
   int from=(int)MathMax(0,shift-1),wanted=shift-from+2;
   MqlRates rates[];
   int got=CopyRates(_Symbol,tf,from,wanted,rates);
   if(got<=0)return true;
   double best=(double)radius*radius;
   datetime snap_time=t;double snap_price=p;bool found=false;
   for(int k=0;k<got;k++)
     {
      double prices[4];prices[0]=rates[k].open;prices[1]=rates[k].high;prices[2]=rates[k].low;prices[3]=rates[k].close;
      for(int q=0;q<4;q++)
        {
         int px=0,py=0;if(!XY(rates[k].time,prices[q],px,py))continue;
         double distance=(double)(px-x)*(px-x)+(double)(py-y)*(py-y);
         if(distance<=best){best=distance;snap_time=rates[k].time;snap_price=prices[q];found=true;}
        }
     }
   if(found){t=snap_time;p=snap_price;}
   return true; // Retain the original chart coordinate outside the magnet radius.
  }
bool Geometry(FPSetup &s,int &xa,int &ya,int &xb,int &yb,int &xl,int &xr)
  {
   if(!XY(s.ta,s.pa,xa,ya) || !XY(s.tb,s.pb,xb,yb))return false;
   int ignore=0;double mid=(s.pa+s.pb)*.5;
   if(!XY(s.left,mid,xl,ignore) || !XY(s.right,mid,xr,ignore))return false;
   return true;
  }

// Binary snapshots are versioned, bounded and verified before replacing live state.
void WText(const int f,const string text){FileWriteInteger(f,StringLen(text),INT_VALUE);FileWriteString(f,text,StringLen(text));}
bool RText(const int f,string &text,const int maxlen)
  {int n=FileReadInteger(f,INT_VALUE);if(n<0 || n>maxlen)return false;if(n==0){text="";return true;}text=FileReadString(f,n);return StringLen(text)==n;}
void WriteSetup(const int f,FPSetup &s)
  {
   FileWriteInteger(f,s.uid);WText(f,s.name);WText(f,s.description);
   FileWriteLong(f,(long)s.ta);FileWriteLong(f,(long)s.tb);FileWriteDouble(f,s.pa);FileWriteDouble(f,s.pb);
   FileWriteLong(f,(long)s.left);FileWriteLong(f,(long)s.right);FileWriteInteger(f,(int)s.source_tf);FileWriteLong(f,s.visible_mask);
   int flags=(s.ray_left?1:0)|(s.ray_right?2:0)|(s.anchors_locked?4:0)|(s.diagonal?8:0)|(s.labels?16:0)|(s.fill?32:0)|(s.gradient?64:0)|(s.fill_rays?128:0);
   flags|=1024|(s.visibility_mode<<8); // Optional flag bits keep schema-1 records compatible.
   flags|=2048|(Lim(s.label_v,0,1)<<12)|(Lim(s.label_h,0,1)<<14)|(s.label_float?32768:0)|(s.hline?65536:0);
   FileWriteInteger(f,flags);FileWriteInteger(f,(int)s.base_color);FileWriteInteger(f,(int)s.fill_top);FileWriteInteger(f,(int)s.fill_bottom);FileWriteInteger(f,s.opacity);FileWriteInteger(f,s.count);
   for(int i=0;i<s.count;i++)
     {FileWriteInteger(f,s.levels[i].enabled?1:0);FileWriteDouble(f,s.levels[i].value);WText(f,s.levels[i].description);
      FileWriteInteger(f,s.levels[i].style);FileWriteInteger(f,s.levels[i].width);FileWriteInteger(f,(int)s.levels[i].ink);}
  }
bool ReadSetup(const int f,FPSetup &s)
  {
   s.uid=FileReadInteger(f);
   if(!RText(f,s.name,120) || !RText(f,s.description,240))return false;
   s.ta=(datetime)FileReadLong(f);s.tb=(datetime)FileReadLong(f);s.pa=FileReadDouble(f);s.pb=FileReadDouble(f);
   s.left=(datetime)FileReadLong(f);s.right=(datetime)FileReadLong(f);s.source_tf=(ENUM_TIMEFRAMES)FileReadInteger(f);s.visible_mask=FileReadLong(f);
   int flags=FileReadInteger(f);
   s.visibility_mode=(flags&1024)!=0?((flags>>8)&3):-1;
   s.ray_left=(flags&1)!=0;s.ray_right=(flags&2)!=0;s.anchors_locked=(flags&4)!=0;s.diagonal=(flags&8)!=0;s.labels=(flags&16)!=0;
   s.fill=(flags&32)!=0;s.gradient=(flags&64)!=0;s.fill_rays=(flags&128)!=0;
   if((flags&2048)!=0){s.label_v=(flags>>12)&3;s.label_h=(flags>>14)&1;s.label_float=(flags&32768)!=0;}
   else {s.label_v=0;s.label_h=0;s.label_float=true;} // Matches the label placement of earlier versions.
   s.hline=(flags&65536)!=0;
   s.base_color=(color)FileReadInteger(f);s.fill_top=(color)FileReadInteger(f);s.fill_bottom=(color)FileReadInteger(f);s.opacity=FileReadInteger(f);s.count=FileReadInteger(f);
   if(s.uid<=0 || s.ta<=0 || s.tb<=0 || s.left>=s.right || TFIndex(s.source_tf)<0 || s.count<0 || s.count>FP_MAX_LEVELS || s.opacity<0 || s.opacity>100 || s.label_v>1)return false;
   if(!MathIsValidNumber(s.pa) || !MathIsValidNumber(s.pb) || s.pa==s.pb)return false;
   s.visible_mask&=FP_ALL_TF_MASK;
   if(s.visibility_mode<0)s.visibility_mode=s.visible_mask==Allowed(s.source_tf)?1:(s.visible_mask==((long)1<<TFIndex(s.source_tf))?2:0);
   if(s.visibility_mode>2)return false;
   for(int i=0;i<s.count;i++)
     {
      int enabled=FileReadInteger(f);s.levels[i].enabled=enabled!=0;s.levels[i].value=FileReadDouble(f);
      if(!RText(f,s.levels[i].description,160))return false;
      s.levels[i].style=FileReadInteger(f);s.levels[i].width=FileReadInteger(f);s.levels[i].ink=(color)FileReadInteger(f);
      if(enabled<0 || enabled>1 || !MathIsValidNumber(s.levels[i].value) || MathAbs(s.levels[i].value)>1000 || s.levels[i].style<0 || s.levels[i].style>4 || s.levels[i].width<1 || s.levels[i].width>5)return false;
     }
   return !FileIsEnding(f);
  }
bool LoadFile(const string filename,const bool install=true)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   bool good=(FileReadInteger(f)==FP_MAGIC && FileReadInteger(f)==FP_SCHEMA);
   int n=0,next=1;
   if(good){next=FileReadInteger(f);n=FileReadInteger(f);good=(n>=0 && n<=FP_MAX_SETUPS && next>0);}
   for(int i=0;good && i<n;i++)good=ReadSetup(f,g_stage[i]);
   if(good)good=(FileReadInteger(f)==FP_END && FileTell(f)==FileSize(f));
   FileClose(f);
   if(!good)return false;
   if(install)
     {g_count=n;g_next_uid=next;for(int i=0;i<n;i++){g_sets[i]=g_stage[i];if(g_sets[i].uid>=g_next_uid)g_next_uid=g_sets[i].uid+1;}}
   return true;
  }
bool Save()
  {
   if(g_store=="" || !g_owner)return false;
   string temporary=g_store+".tmp";
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE){Status("Could not save drawings. Check the Experts log.");Print("Fibonacci Pro FileOpen error ",GetLastError());return false;}
   ResetLastError();FileWriteInteger(f,FP_MAGIC);FileWriteInteger(f,FP_SCHEMA);FileWriteInteger(f,g_next_uid);FileWriteInteger(f,g_count);
   for(int i=0;i<g_count;i++)WriteSetup(f,g_sets[i]);
   FileWriteInteger(f,FP_END);FileFlush(f);int error=GetLastError();FileClose(f);
   if(error!=0){Print("Fibonacci Pro snapshot write failed: ",error);Status("Save failed; previous snapshot retained.");return false;}
   if(!LoadFile(temporary,false)){Status("Snapshot verification failed; previous saved drawings retained.");return false;}
   if(FileIsExist(g_store))
     {
      string destination=g_primary_valid?g_store+".bak":g_store+".unreadable."+IntegerToString((long)GetTickCount64());
      if(!FileCopy(g_store,0,destination,FILE_REWRITE))
        {Status("Backup failed; previous snapshot retained.");return false;}
     }
   if(!FileMove(temporary,0,g_store,FILE_REWRITE)){Status("Snapshot replacement failed; previous snapshot retained.");return false;}
   g_primary_valid=true;g_save_gen++;
   return true;
  }

// PRESET_IO_BEGIN -- the same serialization is used by the local round-trip test.
bool ReadPreset(const string filename,FPSetup &settings)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   FPSetup candidate;
   bool good=(FileReadInteger(f)==FP_PRESET_MAGIC && FileReadInteger(f)==1);
   if(good)good=ReadSetup(f,candidate);
   if(good)good=(FileReadInteger(f)==FP_PRESET_END && FileTell(f)==FileSize(f));
   FileClose(f);if(good)settings=candidate;return good;
  }
bool WritePreset(const string filename,FPSetup &settings)
  {
   FPSetup record=settings,verified;
   // Presets deliberately contain no real instrument prices, dates or names.
   record.uid=1;record.name="Configuration";record.description="";record.hline=false;
   record.ta=1;record.tb=2;record.pa=1;record.pb=0;record.left=1;record.right=2;
   string temporary=filename+".tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();FileWriteInteger(f,FP_PRESET_MAGIC);FileWriteInteger(f,1);WriteSetup(f,record);FileWriteInteger(f,FP_PRESET_END);
   FileFlush(f);int error=GetLastError();FileClose(f);
   if(error!=0 || !ReadPreset(temporary,verified) || !SameConfig(record,verified))return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }
// PRESET_IO_END
bool RememberConfig(FPSetup &settings)
  {
   // Horizontal lines keep a single level on; they must not become the template for new Fibs.
   if(settings.hline)return true;
   if(g_has_last_config && g_last_config_persisted && SameConfig(settings,g_last_config))return true;
   g_last_config=settings;g_has_last_config=true;
   g_last_config_persisted=WritePreset(g_last_store,g_last_config);
   if(g_last_config_persisted)return true;
   Status("Drawing settings kept in memory; saving last-used configuration failed.");
   Print("Fibonacci Pro could not persist last-used configuration: ",GetLastError());return false;
  }
void SaveLayout()
  {
   if(g_layout_store=="" || !g_owner)return;
   string temporary=g_layout_store+".tmp";
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE){Status("Could not save toolbar position.");return;}
   ResetLastError();FileWriteInteger(f,FP_LAYOUT_MAGIC);FileWriteDouble(f,g_toolbar_lx);FileWriteDouble(f,g_toolbar_ly);FileWriteInteger(f,FP_END);
   FileFlush(f);int error=GetLastError();FileClose(f);
   if(error!=0 || !FileMove(temporary,0,g_layout_store,FILE_REWRITE))Status("Could not save toolbar position.");
  }
void LoadLayout()
  {
   int f=FileOpen(g_layout_store,FILE_READ|FILE_BIN|FILE_SHARE_READ);if(f==INVALID_HANDLE)return;
   bool good=FileReadInteger(f)==FP_LAYOUT_MAGIC;
   double x=FileReadDouble(f),y=FileReadDouble(f);
   good=good && FileReadInteger(f)==FP_END && FileTell(f)==FileSize(f);
   FileClose(f);
   if(good && MathIsValidNumber(x) && MathIsValidNumber(y) && x>=0 && y>=0 && x<100000 && y<100000){g_toolbar_lx=x;g_toolbar_ly=y;}
  }

// Native chart UI. Compact 2 px column gutters replace conventional 8 px gaps.
// Object commands are asynchronous in MT5, but ObjectFind/ObjectGet* wait for the
// whole chart command queue. The registry below answers those questions locally.
int RegFind(const string name)
  {
   for(int k=0;k<g_reg_count;k++)
     {int i=(g_reg_hint+k)%g_reg_count;if(g_reg[i].name==name){g_reg_hint=i+1;return i;}}
   return -1;
  }
void RegDrop(const int i)
  {g_reg_count--;if(i<g_reg_count)g_reg[i]=g_reg[g_reg_count];g_reg_hint=0;}
void RegDelete(const string name)
  {int i=RegFind(name);if(i<0)return;ObjectDelete(0,name);RegDrop(i);}
void RegDeletePrefix(const string prefix)
  {
   bool any=false;
   for(int i=g_reg_count-1;i>=0;i--)if(StringFind(g_reg[i].name,prefix)==0){any=true;RegDrop(i);}
   if(any)ObjectsDeleteAll(0,prefix);
  }
// Remove objects under prefix that the current build generation did not touch.
void RegSweep(const string prefix)
  {
   for(int i=g_reg_count-1;i>=0;i--)
      if(g_reg[i].gen!=g_gen && StringFind(g_reg[i].name,prefix)==0){ObjectDelete(0,g_reg[i].name);RegDrop(i);}
  }
int RegType(const string name){int i=RegFind(name);return i<0?-1:g_reg[i].type;}
void SetText(const string name,const string text)
  {int i=RegFind(name);if(i<0)return;ObjectSetString(0,name,OBJPROP_TEXT,text);g_reg[i].text=text;g_reg[i].textset=true;}
void UIBase(const string name,const ENUM_OBJECT type,const int x,const int y,const int w,const int h,const string text,const color bg=clrWhite,const color fg=clrBlack,const int z=100)
  {
   int i=RegFind(name);
   if(i<0)
     {
      if(g_reg_count>=FP_REG_MAX)return;
      if(!ObjectCreate(0,name,type,0,0,0))return;
      i=g_reg_count++;
      g_reg[i].name=name;g_reg[i].type=(int)type;g_reg[i].x=FP_OFF;g_reg[i].y=FP_OFF;g_reg[i].w=-1;g_reg[i].h=-1;
      g_reg[i].z=-1;g_reg[i].fs=-1;g_reg[i].bg=-2;g_reg[i].fg=-2;g_reg[i].text="";g_reg[i].textset=false;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      if(type!=OBJ_RECTANGLE_LABEL)ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI");
      if(type==OBJ_BUTTON || type==OBJ_EDIT)ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
      if(type==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
      if(type==OBJ_EDIT){ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_LEFT);ObjectSetInteger(0,name,OBJPROP_READONLY,false);}
      if(type==OBJ_RECTANGLE_LABEL){ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetInteger(0,name,OBJPROP_COLOR,clrSilver);}
     }
   g_reg[i].gen=g_gen;
   // Only changed properties are sent to the terminal.
   if(g_reg[i].x!=x){ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);g_reg[i].x=x;}
   if(g_reg[i].y!=y){ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);g_reg[i].y=y;}
   if(type!=OBJ_LABEL)
     {
      if(g_reg[i].w!=w){ObjectSetInteger(0,name,OBJPROP_XSIZE,w);g_reg[i].w=w;}
      if(g_reg[i].h!=h){ObjectSetInteger(0,name,OBJPROP_YSIZE,h);g_reg[i].h=h;}
      if(g_reg[i].bg!=(int)bg){ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);g_reg[i].bg=(int)bg;}
     }
   if(type!=OBJ_RECTANGLE_LABEL)
     {
      if(g_reg[i].fg!=(int)fg){ObjectSetInteger(0,name,OBJPROP_COLOR,fg);g_reg[i].fg=(int)fg;}
      int fs=(int)MathMax(8,U(9));
      if(g_reg[i].fs!=fs){ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);g_reg[i].fs=fs;}
      // Edit boxes are always rewritten: their on-screen text can differ from the cache.
      if(type==OBJ_EDIT || !g_reg[i].textset || g_reg[i].text!=text)
        {ObjectSetString(0,name,OBJPROP_TEXT,text);g_reg[i].text=text;g_reg[i].textset=true;}
     }
   if(g_reg[i].z!=z){ObjectSetInteger(0,name,OBJPROP_ZORDER,z);g_reg[i].z=z;}
  }
void Button(const string key,const string text,const int x,const int y,const int w,const int h=22,const color bg=clrWhite)
  {double luminance=.299*((int)bg&255)+.587*(((int)bg>>8)&255)+.114*(((int)bg>>16)&255);UIBase(UIS(key),OBJ_BUTTON,x,y,U(w),U(h),text,bg,luminance<145?clrWhite:clrBlack);}
void Label(const string key,const string text,const int x,const int y,const color fg=clrBlack)
  {UIBase(UIS(key),OBJ_LABEL,x,y,0,0,text,clrWhite,fg);}
void Edit(const string key,const string text,const int x,const int y,const int w)
  {UIBase(UIS(key),OBJ_EDIT,x,y,U(w),U(22),text);}
void Check(const string key,const string text,const bool value,const int x,const int y,const int w)
  {Button(key,(value?"[x] ":"[ ] ")+text,x,y,w);}
void Box(const string key,const int x,const int y,const int w,const int h,const color bg)
  {UIBase(UIS(key),OBJ_RECTANGLE_LABEL,x,y,U(w),U(h),"",bg,clrBlack,90);}
void Tooltip(const string key,const string text)
  {if(RegFind(UIS(key))>=0)ObjectSetString(0,UIS(key),OBJPROP_TOOLTIP,text);}
int PanelHeight(){return U(184+g_rows*24);}
void ClosePopup()
  {RegDeletePrefix(Obj("P."));RegDeletePrefix(Obj("D."));RegDeletePrefix(Obj("R."));RegDeletePrefix(Obj("Q."));if(g_picker_ready){g_picker.Destroy();g_picker_ready=false;}g_popup=0;g_picker_drag=0;}
void CloseEditor()
  {ClosePopup();g_editor=false;g_slider_drag=false;g_ui_dirty=true;g_dirty=true;}
void OpenEditor()
  {
   if(g_selected<0 || g_selected>=g_count){Status("Select a Fibonacci drawing first.");return;}
   if(g_zeditor){Status("Close the Zones window first.");return;}
   if(g_drag!=0 || g_armed)return;
   ClosePopup();g_list=false;g_edit=g_sets[g_selected];g_editor=true;g_page=0;g_ui_dirty=true;g_dirty=true;
  }
bool ApplyEditor(const bool close)
  {
   if(!g_editor || g_selected<0 || g_selected>=g_count)return false;
   if(!HarvestEdits())return false;
   if(g_edit.pa==g_edit.pb || g_edit.left>=g_edit.right){Status("Anchors need different prices and a positive horizontal span.");return false;}
   g_edit.visible_mask&=FP_ALL_TF_MASK;
   FPSetup previous=g_sets[g_selected];g_sets[g_selected]=g_edit;
   if(!Save()){g_sets[g_selected]=previous;g_dirty=true;return false;}
   if(!RememberConfig(g_edit)){g_dirty=true;return false;}
   g_dirty=true;
   if(!Visible(g_edit))Status("Saved. This drawing is hidden on "+g_tf_names[g_tf]+" (see Visualization).");
   else Status(g_edit.hline?"Horizontal line saved.":"Drawing and last-used configuration saved.");
   if(close)CloseEditor();else{ClosePopup();g_ui_dirty=true;}
   return true;
  }
void ToggleUI()
  {
   if(g_toolbar_drag || g_drag!=0)return;
   if(g_armed)CancelDrag();
   if(!g_hidden && g_editor && !HarvestEdits())return;
   if(!g_hidden && g_zeditor && !HarvestZoneEdits())return;
   ClosePopup();g_hidden=!g_hidden;g_ui_dirty=true;
  }
void DuplicateSelected()
  {
   if(g_drag!=0 || g_armed || g_toolbar_drag)return;
   if(g_selected<0 || g_selected>=g_count){Status("Highlight a visible custom Fib before duplicating.");return;}
   if(g_count>=MaxSetups()){Status("Drawing limit reached ("+IntegerToString(MaxSetups())+"); delete a drawing or raise InpMaximumSetups.");return;}
   FPSetup source=g_sets[g_selected];
   if(g_editor){if(!HarvestEdits())return;source=g_edit;}
   if(!Visible(source)){Status("Highlight a visible custom Fib before duplicating.");return;}
   int slot=g_count,uid=g_next_uid;
   CopyDuplicate(g_sets[slot],source,uid);g_count++;g_next_uid++;
   if(!Save()){g_count--;g_next_uid--;return;}
   CloseEditor();g_selected=slot;g_dirty=true;g_ui_dirty=true;
   if(RememberConfig(g_sets[slot]))Status("Duplicate selected at the same anchors. Drag its middle handle to move it.");
  }
// Status line under the toolbar: messages used to be visible only in a tooltip, so a
// refused action (for example the drawing limit) looked like the tool had stopped.
void UpdateStatusObjects(const ulong now)
  {
   g_status_dirty=false;
   bool show=g_owner && !g_hidden && now<g_status_until && StringLen(g_status)>0;
   if(!show)
     {if(g_status_shown){RegDelete(UIS("T.StatusBG"));RegDelete(UIS("T.Status"));g_status_shown=false;}return;}
   string text=Clip(g_status,120);
   int x=g_toolbar_x+U(8),y=g_toolbar_y+U(FP_TOOLBAR_HEIGHT+2);
   int w=(int)MathMin(MathMax(U(60),g_width-x-4),U(16)+StringLen(text)*U(6));
   UIBase(UIS("T.StatusBG"),OBJ_RECTANGLE_LABEL,x,y,w,U(20),"",clrLightYellow,clrBlack,95);
   UIBase(UIS("T.Status"),OBJ_LABEL,x+U(6),y+U(3),0,0,text,clrWhite,clrBlack,100);
   g_status_shown=true;
  }
void BuildToolbar()
  {
   int x=g_toolbar_x,y=g_toolbar_y;
   // No toolbar background object: the chart remains visible between controls.
   Label("T.Grip",":: Fibonacci Pro "+g_version+"   (drag to move)",x+U(7),y+U(3),g_chart_fg);
   string title=g_selected>=0 && g_selected<g_count?g_sets[g_selected].name:"No selection";
   Tooltip("T.Grip",title+" | "+g_status+" | Drag title to move");
   Button("T.Close",Glyph(0xD7),x+U(FP_TOOLBAR_WIDTH-28),y+U(1),20,18);
   Tooltip("T.Close","Detach Fibonacci Pro from this chart (saved drawings retained)");
   UpdateZonesButton();
   x+=U(8);y+=U(23);
   Button("T.New",g_armed?"Draw now...":"New Fib",x,y,78,22,g_armed?clrLightSteelBlue:clrWhite);
   Tooltip("T.New","Then press-drag-release for a Fib with the last used levels, or single-click for a horizontal line snapped to OHLC");
   x+=U(80);
   Button("T.Prev","<",x,y,23);x+=U(25);
   Button("T.Next",">",x,y,23);x+=U(25);
   Button("T.List","List",x,y,44,22,g_list?clrLightSteelBlue:clrWhite);x+=U(46);
   Tooltip("T.List","All drawings: search, filter, sort, show/hide, go to, edit, delete");
   Button("T.Properties","Properties",x,y,82);x+=U(84);
   Button("T.Duplicate","Duplicate",x,y,72);x+=U(74);
   Button("T.Delete","Delete",x,y,52);x+=U(54);
   Button("T.Hide","Hide UI",x,y,60);
  }
void PlaceOpacityThumb()
  {
   if(!g_slider_on)return;
   int value=g_zeditor?g_zedit.opacity:g_edit.opacity;
   int tx=g_slider_x0+(int)MathRound((g_slider_x1-g_slider_x0)*value/100.0)-U(5);
   Box(g_zeditor?"Z.OpThumb":"E.OpThumb",tx,g_slider_y0+U(3),10,20,clrDimGray);
  }
string LabelVText(const int v){return v==1?"Below line":"Above line";}
string LabelHText(const int h){return h==1?"Right (end)":"Left (origin)";}
string LabelFText(const bool f){return f?"Float at edge":"Fixed at end";}
void BuildEditor()
  {
   int x=g_panel_x,y=g_panel_y;
   Box("E.Background",x,y,FP_PANEL_WIDTH,184+g_rows*24,clrWhiteSmoke);
   Label("E.Title","Fibonacci Pro - "+g_edit.name,x+U(10),y+U(7));
   string tabs[]={"Common","Parameters","Fibo levels","Visualization","Fill"};
   int widths[]={72,91,90,104,55};int tx=x+U(10);
   for(int t=0;t<5;t++){Button("E.Tab"+IntegerToString(t),tabs[t],tx,y+U(30),widths[t],23,t==g_tab?clrWhite:clrGainsboro);tx+=U(widths[t]+2);}
   int cy=y+U(64);
   if(g_tab==0)
     {
      Label("E.NL","Name",x+U(12),cy+U(4));Edit("E.Name",g_edit.name,x+U(95),cy,350);cy+=U(28);
      Label("E.DL","Description",x+U(12),cy+U(4));Edit("E.Description",g_edit.description,x+U(95),cy,350);cy+=U(32);
      Check("E.Labels","Show level labels",g_edit.labels,x+U(12),cy,150);
      Button("E.LblV",LabelVText(g_edit.label_v)+" v",x+U(166),cy,92);
      Button("E.LblH",LabelHText(g_edit.label_h)+" v",x+U(260),cy,100);
      Button("E.LblF",LabelFText(g_edit.label_float)+" v",x+U(362),cy,114);
      Tooltip("E.LblV","Label above or below its level line");
      Tooltip("E.LblH","Label at the origin (left) or the end (right) of the Fib");
      Tooltip("E.LblF","Float: labels stay in the window and sit at the chart edge when the level is rayed. Fixed: labels stay at the Fib's own end");
      cy+=U(27);
      Check("E.Diagonal","Show anchor diagonal",g_edit.diagonal,x+U(12),cy,200);cy+=U(27);
      Check("E.Lock","Lock price-anchor handles",g_edit.anchors_locked,x+U(12),cy,240);cy+=U(27);
      Check("E.LineMode","Horizontal line mode (move by origin handle)",g_edit.hline,x+U(12),cy,330);cy+=U(30);
      Tooltip("E.LineMode","Shows one origin handle on the first enabled level; dragging it or the line snaps to OHLC and keeps the line horizontal");
      Button("E.BaseColor","Diagonal color",x+U(12),cy,130,22,g_edit.base_color);
     }
   if(g_tab==1)
     {
      int source=TFIndex(g_edit.source_tf);
      Label("E.SrcTF","Drawn on "+(source>=0?g_tf_names[source]:"?")+" (fixed)",x+U(12),cy);cy+=U(29);
      Label("E.A","Anchor A",x+U(12),cy+U(4));Edit("E.TimeA",TimeToString(g_edit.ta,TIME_DATE|TIME_SECONDS),x+U(88),cy,195);Edit("E.PriceA",DoubleToString(g_edit.pa,_Digits),x+U(285),cy,160);cy+=U(28);
      Label("E.B","Anchor B",x+U(12),cy+U(4));Edit("E.TimeB",TimeToString(g_edit.tb,TIME_DATE|TIME_SECONDS),x+U(88),cy,195);Edit("E.PriceB",DoubleToString(g_edit.pb,_Digits),x+U(285),cy,160);cy+=U(28);
      Label("E.L","Left extent",x+U(12),cy+U(4));Edit("E.Left",TimeToString(g_edit.left,TIME_DATE|TIME_SECONDS),x+U(110),cy,235);cy+=U(28);
      Label("E.R","Right extent",x+U(12),cy+U(4));Edit("E.Right",TimeToString(g_edit.right,TIME_DATE|TIME_SECONDS),x+U(110),cy,235);cy+=U(31);
      Check("E.RayL","Ray left",g_edit.ray_left,x+U(12),cy,130);Check("E.RayR","Ray right",g_edit.ray_right,x+U(150),cy,130);
     }
   if(g_tab==2)
     {
      // 2 px between editable columns -- 75% less than an 8 px baseline.
      int cols[]={12,42,108,220,326,374,428};
      string heads[]={"On","Level","Description","Style","Width","Color",""};
      for(int c=0;c<7;c++)Label("E.Head"+IntegerToString(c),heads[c],x+U(cols[c]),cy);
      cy+=U(21);int start=g_page*g_rows;
      for(int row=0;row<g_rows && start+row<g_edit.count;row++)
        {
         int i=start+row;string n=IntegerToString(i);int ry=cy+U(row*24);
         Button("E.On"+n,g_edit.levels[i].enabled?"x":"",x+U(cols[0]),ry,28);
         Edit("E.Value"+n,RatioText(g_edit.levels[i].value),x+U(cols[1]),ry,64);
         Edit("E.Text"+n,g_edit.levels[i].description,x+U(cols[2]),ry,110);
         Button("E.Style"+n,g_style_names[g_edit.levels[i].style]+" v",x+U(cols[3]),ry,104);
         Button("E.Width"+n,IntegerToString(g_edit.levels[i].width)+" v",x+U(cols[4]),ry,46);
         Button("E.Color"+n,"",x+U(cols[5]),ry,52,22,g_edit.levels[i].ink);
         Button("E.Remove"+n,"x",x+U(cols[6]),ry,25);
        }
      int fy=y+PanelHeight()-U(93);
      Button("E.Add","Add",x+U(12),fy,52);Button("E.Defaults","Defaults",x+U(66),fy,70);
      Button("E.PageBack","<",x+U(270),fy,26);Button("E.PageNext",">",x+U(298),fy,26);
      bool uniform=g_edit.count>0;
      for(int i=1;i<g_edit.count && uniform;i++)uniform=g_edit.levels[i].ink==g_edit.levels[0].ink;
      Button("E.AllColor","All",x+U(cols[5]),fy,52,22,uniform?g_edit.levels[0].ink:clrWhite);
      Tooltip("E.AllColor","Set every level to one colour");
      Label("E.Page",IntegerToString(g_page+1)+" / "+IntegerToString((int)MathMax(1,(g_edit.count+g_rows-1)/g_rows)),x+U(336),fy+U(4));
     }
   if(g_tab==3)
     {
      int source=TFIndex(g_edit.source_tf);
      Label("E.VTitle","Show on timeframes (drawn on "+(source>=0?g_tf_names[source]:"?")+"; higher ones are optional)",x+U(12),cy);cy+=U(30);
      for(int i=0;i<FP_TF_COUNT;i++)
        {
         string text=(((g_edit.visible_mask&((long)1<<i))!=0)?"[x] ":"[ ] ")+g_tf_names[i];
         Button("E.TF"+IntegerToString(i),text,x+U(12+(i%5)*90),cy+U((i/5)*30),84,24,i==source?clrLavender:(i>source?clrIvory:clrWhite));
        }
      Button("E.AllLower","Drawing TF & lower",x+U(12),cy+U(159),128);
      Button("E.OnlySource","Drawing TF only",x+U(144),cy+U(159),116);
      Button("E.AllTF","All timeframes",x+U(264),cy+U(159),110);
     }
   if(g_tab==4)
     {
      Check("E.Fill","Enable transparent fill",g_edit.fill,x+U(12),cy,230);cy+=U(29);
      Check("E.Gradient","Vertical gradient",g_edit.gradient,x+U(12),cy,230);cy+=U(29);
      Check("E.FillRays","Fill follows left/right rays",g_edit.fill_rays,x+U(12),cy,260);cy+=U(32);
      Button("E.FillTop","Top / solid color",x+U(12),cy,180,24,g_edit.fill_top);
      Button("E.FillBottom","Bottom color",x+U(198),cy,180,24,g_edit.fill_bottom);cy+=U(36);
      Label("E.OpacityLabel","Opacity %",x+U(12),cy+U(4));Edit("E.Opacity",IntegerToString(g_edit.opacity),x+U(84),cy,48);
      g_slider_x0=x+U(148);g_slider_x1=x+U(466);g_slider_y0=cy-U(2);g_slider_y1=cy+U(24);g_slider_on=true;
      Box("E.OpTrack",g_slider_x0,cy+U(9),318,5,clrSilver);
      PlaceOpacityThumb();
     }
   int by=y+PanelHeight()-U(31);
   Button("E.Save","Save",x+U(316),by-U(30),72);Button("E.Load","Load",x+U(390),by-U(30),72);
   Button("E.OK","OK",x+U(242),by,72);Button("E.Cancel","Cancel",x+U(316),by,72);Button("E.Apply","Apply",x+U(390),by,72);
  }
void BuildUI()
  {
   g_ui_dirty=false;g_gen++;g_slider_on=false;
   g_chart_fg=(color)ChartGetInteger(0,CHART_COLOR_FOREGROUND);g_chart_bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   // Stable object identities: unchanged controls are left alone, stale ones are swept.
   if(!g_hidden){BuildToolbar();if(g_editor)BuildEditor();else if(g_zeditor)BuildZonesPanel();else if(g_list)BuildList();}
   UpdateStatusObjects(GetTickCount64());
   RegSweep(UIS(""));
  }

void RefreshPresetList()
  {
   g_preset_count=0;string filename,ext=g_preset_zones?".fzp":".fpp";
   long search=FileFindFirst("FibonacciPro\\Presets\\*"+ext,filename);
   if(search!=INVALID_HANDLE)
     {
      do
        {int n=StringLen(filename);if(n>4 && g_preset_count<254 && StringSubstr(filename,n-4)==ext)g_preset_names[g_preset_count++]=StringSubstr(filename,0,n-4);}
      while(FileFindNext(search,filename));
      FileFindClose(search);
     }
   for(int i=0;i<g_preset_count-1;i++)for(int j=i+1;j<g_preset_count;j++)
     if(StringCompare(g_preset_names[i],g_preset_names[j])>0){string temp=g_preset_names[i];g_preset_names[i]=g_preset_names[j];g_preset_names[j]=temp;}
   if(g_preset_zones)
     {
      // Built-in zone presets come first; they are generated, not files.
      for(int i=g_preset_count-1;i>=0;i--)g_preset_names[i+2]=g_preset_names[i];
      g_preset_names[0]=FPZ_BUILTIN_FX;g_preset_names[1]=FPZ_BUILTIN_IDX;g_preset_count+=2;
     }
  }
void PresetMessage(const string text)
  {SetText(Obj("R.Message"),StringSubstr(text,0,52));ChartRedraw();}
void HarvestPresetName()
  {if(RegFind(Obj("R.Name"))>=0)g_preset_name=ObjectGetString(0,Obj("R.Name"),OBJPROP_TEXT);}
void PresetBrowser(const bool save_mode,const bool reset_page=true,const bool harvest=true)
  {
   if(!g_editor && !g_zeditor)return;
   if(g_popup==4 && harvest)HarvestPresetName();
   ClosePopup();g_popup=4;g_preset_save=save_mode;g_preset_zones=g_zeditor;
   if(reset_page){RefreshPresetList();g_preset_page=0;}
   g_preset_page=Lim(g_preset_page,0,(int)MathMax(0,(g_preset_count-1)/7));
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(20);
   if(g_popup_y+U(326)>g_height)g_popup_y=(int)MathMax(4,g_height-U(326)-4);
   int px=g_popup_x,py=g_popup_y;
   UIBase(Obj("R.Background"),OBJ_RECTANGLE_LABEL,px,py,U(360),U(326),"",clrWhiteSmoke,clrBlack,390);
   UIBase(Obj("R.Title"),OBJ_LABEL,px+U(10),py+U(8),0,0,g_preset_zones?(save_mode?"Save zones preset":"Load or delete a zones preset"):(save_mode?"Save configuration preset":"Load or delete a configuration preset"),clrWhite,clrBlack,400);
   UIBase(Obj("R.Name"),OBJ_EDIT,px+U(10),py+U(34),U(338),U(24),g_preset_name,clrWhite,clrBlack,400);
   for(int row=0;row<7;row++)
     {
      int i=g_preset_page*7+row;if(i>=g_preset_count)break;
      bool current=g_preset_names[i]==g_preset_name;
      UIBase(Obj("R.Item"+IntegerToString(i)),OBJ_BUTTON,px+U(10),py+U(68+row*23),U(338),U(22),g_preset_names[i],current?clrLightSteelBlue:clrWhite,clrBlack,400);
     }
   UIBase(Obj("R.Prev"),OBJ_BUTTON,px+U(10),py+U(236),U(28),U(23),"<",clrWhite,clrBlack,400);
   UIBase(Obj("R.Next"),OBJ_BUTTON,px+U(40),py+U(236),U(28),U(23),">",clrWhite,clrBlack,400);
   UIBase(Obj("R.Page"),OBJ_LABEL,px+U(80),py+U(240),0,0,IntegerToString(g_preset_page+1)+" / "+IntegerToString((int)MathMax(1,(g_preset_count+6)/7)),clrWhite,clrBlack,400);
   UIBase(Obj("R.Message"),OBJ_LABEL,px+U(10),py+U(267),0,0,save_mode?"Choose a name; saving replaces that named preset.":(g_preset_zones?"Loading replaces the zone list; broker time is kept.":"Choose a preset; anchors stay unchanged."),clrWhite,clrBlack,400);
   if(!save_mode)UIBase(Obj("R.Delete"),OBJ_BUTTON,px+U(100),py+U(292),U(80),U(24),"Delete",clrMistyRose,clrBlack,400);
   UIBase(Obj("R.Action"),OBJ_BUTTON,px+U(184),py+U(292),U(80),U(24),save_mode?"Save":"Load",clrWhite,clrBlack,400);
   UIBase(Obj("R.Cancel"),OBJ_BUTTON,px+U(268),py+U(292),U(80),U(24),"Cancel",clrWhite,clrBlack,400);
   ChartRedraw();
  }
bool PresetNameValid()
  {
   StringTrimLeft(g_preset_name);StringTrimRight(g_preset_name);
   return !(g_preset_name=="" || StringLen(g_preset_name)>80 || SafeName(g_preset_name)!=g_preset_name || g_preset_name=="." || g_preset_name==".." || StringSubstr(g_preset_name,StringLen(g_preset_name)-1)==".");
  }
void PresetAction()
  {
   if((!g_editor && !g_zeditor) || g_popup!=4)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Use a short name without path or special characters.");return;}
   if(g_preset_zones){ZonePresetAction();return;}
   string filename="FibonacciPro\\Presets\\"+g_preset_name+".fpp";
   if(g_preset_save)
     {
      if(!HarvestEdits()){PresetMessage("Correct the invalid properties before saving.");return;}
      if(!WritePreset(filename,g_edit)){PresetMessage("Could not save preset. Check Experts log.");Print("Fibonacci Pro preset write error: ",GetLastError());return;}
      // Save is an explicit commit, not just a file export of an uncommitted draft.
      if(!ApplyEditor(false)){ClosePopup();Status("Preset file saved; applying or autosaving settings failed.");return;}
      Status("Saved preset: "+g_preset_name+". New Fibs inherit these settings.");
     }
   else
     {
      FPSetup loaded;
      if(!ReadPreset(filename,loaded) && !ReadPreset(filename+".bak",loaded)){PresetMessage("Preset missing or invalid; current settings retained.");return;}
      CopyConfig(g_edit,loaded);g_page=0;ClosePopup();g_dirty=true;g_ui_dirty=true;
      Status("Loaded "+g_preset_name+". Apply or OK to keep it; Cancel to revert.");
     }
  }
// Two-step delete: the first click arms, a second click within 5 s removes the file.
void PresetDelete()
  {
   if((!g_editor && !g_zeditor) || g_popup!=4 || g_preset_save)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Select a preset to delete.");return;}
   if(g_preset_zones && ZoneBuiltin(g_preset_name)){PresetMessage("Built-in presets can't be deleted.");return;}
   string filename="FibonacciPro\\Presets\\"+g_preset_name+(g_preset_zones?".fzp":".fpp");
   if(!FileIsExist(filename)){PresetMessage("No saved preset named \""+Clip(g_preset_name,24)+"\".");return;}
   ulong now=GetTickCount64();
   if(g_delete_confirm!=g_preset_name || now>g_delete_confirm_until)
     {
      g_delete_confirm=g_preset_name;g_delete_confirm_until=now+5000;
      PresetMessage("Click Delete again to remove \""+Clip(g_preset_name,24)+"\".");return;
     }
   g_delete_confirm="";
   ResetLastError();
   if(!FileDelete(filename)){PresetMessage("Could not delete preset. Check Experts log.");Print("Fibonacci Pro preset delete error: ",GetLastError());return;}
   if(FileIsExist(filename+".bak"))FileDelete(filename+".bak");
   string removed=g_preset_name;
   g_preset_name="";RefreshPresetList();
   PresetBrowser(false,false,false);
   PresetMessage("Deleted preset \""+Clip(removed,30)+"\".");
  }

void Dropdown(const int kind,const int row)
  {
   bool zone=kind>=10;
   if(zone?!g_zeditor:!g_editor)return;
   if((kind==1 || kind==2) && (row<0 || row>=g_edit.count))return;
   if(kind>=10 && kind<=12 && (row<0 || row>=g_zedit.count))return;
   string source=zone?(kind==10?UIS("Z.Style"+IntegerToString(row)):(kind==11?UIS("Z.Width"+IntegerToString(row)):(kind==12?UIS("Z.Label"+IntegerToString(row)):UIS("Z.Broker")))):kind==1?UIS("E.Style"+IntegerToString(row)):(kind==2?UIS("E.Width"+IntegerToString(row)):(kind==5?UIS("E.LblV"):(kind==6?UIS("E.LblH"):UIS("E.LblF"))));
   int ri=RegFind(source);if(ri<0)return;
   int sx=g_reg[ri].x,sy=g_reg[ri].y,sh=g_reg[ri].h;
   ClosePopup();g_popup=kind;g_popup_row=row;
   string items[];int current=0,w=110;
   if(kind==1){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=g_style_names[i];current=g_edit.levels[row].style;}
   else if(kind==2){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=IntegerToString(i+1);current=g_edit.levels[row].width-1;w=48;}
   else if(kind==5){ArrayResize(items,2);items[0]=LabelVText(0);items[1]=LabelVText(1);current=g_edit.label_v;w=120;}
   else if(kind==6){ArrayResize(items,2);items[0]=LabelHText(0);items[1]=LabelHText(1);current=g_edit.label_h;w=130;}
   else if(kind==7){ArrayResize(items,2);items[0]="Fixed at fib end";items[1]="Float at chart edge (rays)";current=g_edit.label_float?1:0;w=180;}
   else if(kind==10){ArrayResize(items,6);for(int i=0;i<6;i++)items[i]=ZStyleItem(i);current=g_zedit.zones[row].style;w=130;}
   else if(kind==11){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=IntegerToString(i+1);current=g_zedit.zones[row].width-1;w=48;}
   else if(kind==12){ArrayResize(items,3);for(int i=0;i<3;i++)items[i]=ZLabelItem(i);current=g_zedit.zones[row].label;w=110;}
   else {ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=ZoneBrokerText(i);current=g_zedit.broker_mode;w=180;}
   int n=ArraySize(items);
   g_popup_items=n;g_popup_w=U(w);g_popup_h=U(23*n);
   g_popup_x=sx;g_popup_y=sy+sh+U(1);
   if(g_popup_y+g_popup_h>g_height)g_popup_y=(int)MathMax(0,sy-g_popup_h-U(1));
   if(g_popup_x+g_popup_w>g_width)g_popup_x=(int)MathMax(0,g_width-g_popup_w);
   for(int i=0;i<n;i++)
      UIBase(Obj("D."+IntegerToString(i)),OBJ_BUTTON,g_popup_x,g_popup_y+U(23*i),g_popup_w,U(23),items[i],i==current?clrLightSteelBlue:clrWhite,clrBlack,300);
   ChartRedraw();
  }
void DropdownChoice(const int choice)
  {
   if(choice<0 || choice>=g_popup_items)return;
   if(g_popup>=10 && g_popup<=13)
     {
      if(!g_zeditor)return;
      if(g_popup==13){g_zedit.broker_mode=choice;ZonePreview(true);return;}
      if(g_popup_row<0 || g_popup_row>=g_zedit.count)return;
      if(g_popup==10)g_zedit.zones[g_popup_row].style=choice;
      else if(g_popup==11)g_zedit.zones[g_popup_row].width=choice+1;
      else g_zedit.zones[g_popup_row].label=choice;
      ZonePreview(false);return;
     }
   if(!g_editor)return;
   if(g_popup==1 || g_popup==2)
     {
      if(g_popup_row<0 || g_popup_row>=g_edit.count)return;
      if(g_popup==1)g_edit.levels[g_popup_row].style=choice;else g_edit.levels[g_popup_row].width=choice+1;
     }
   else if(g_popup==5)g_edit.label_v=choice;
   else if(g_popup==6)g_edit.label_h=choice;
   else if(g_popup==7)g_edit.label_float=choice==1;
  }
void RGBtoHSV(const color ink)
  {
   double r=((int)ink&255)/255.0,g=(((int)ink>>8)&255)/255.0,b=(((int)ink>>16)&255)/255.0;
   double hi=MathMax(r,MathMax(g,b)),lo=MathMin(r,MathMin(g,b)),d=hi-lo;
   g_value=hi;g_saturation=hi==0?0:d/hi;g_hue=0;
   if(d>0){if(hi==r)g_hue=60*MathMod((g-b)/d,6);else if(hi==g)g_hue=60*((b-r)/d+2);else g_hue=60*((r-g)/d+4);}
   if(g_hue<0)g_hue+=360;
  }
// The saturation/value square is a linear mix of white, the pure hue and black, so each
// pixel needs a few multiplications instead of a full HSV conversion.
void DrawPicker()
  {
   if(!g_picker_ready)return;
   int w=g_picker.Width(),h=g_picker.Height(),square=w-U(34);
   g_picker.Erase(ColorToARGB(clrWhite));
   color pure=FPHSV(g_hue,1,1);
   double hr=((int)pure&255)/255.0,hg=(((int)pure>>8)&255)/255.0,hb=(((int)pure>>16)&255)/255.0;
   double sx_den=MathMax(1,square-1),sy_den=MathMax(1,h-1);
   const uint opaque=0xFF000000;
   for(int y=0;y<h;y++)
     {
      double v=255.0*(1.0-(double)y/sy_den);
      for(int x=0;x<square;x++)
        {
         double s=(double)x/sx_den;
         uint r=(uint)(v*(1.0-s+s*hr)+.5),g=(uint)(v*(1.0-s+s*hg)+.5),b=(uint)(v*(1.0-s+s*hb)+.5);
         g_picker.PixelSet(x,y,opaque|(r<<16)|(g<<8)|b);
        }
     }
   for(int y=0;y<h;y++)g_picker.FillRectangle(square+U(10),y,w-1,y,ColorToARGB(FPHSV((double)y/sy_den*359.99,1,1)));
   int sx=(int)MathRound(g_saturation*(square-1)),sy=(int)MathRound((1-g_value)*(h-1));
   g_picker.Rectangle(Lim(sx-3,0,square-1),Lim(sy-3,0,h-1),Lim(sx+3,0,square-1),Lim(sy+3,0,h-1),ColorToARGB(clrBlack));
   int hy=(int)MathRound(g_hue/359.99*(h-1));
   g_picker.Rectangle(square+U(8),Lim(hy-2,0,h-1),w-1,Lim(hy+2,0,h-1),ColorToARGB(clrBlack));
   g_picker.Update(false);
   if(RegFind(Obj("P.Sample"))>=0)ObjectSetInteger(0,Obj("P.Sample"),OBJPROP_BGCOLOR,g_pick_color);
   ChartRedraw();
  }
void PickApply(const color ink)
  {
   if(g_picker_target<=-1000)
     {
      int z=-g_picker_target-1000;
      if(g_zeditor && z<g_zedit.count)g_zedit.zones[z].ink=ink;
      ClosePopup();ZonePreview(false);g_ui_dirty=true;return;
     }
   if(g_picker_target>=0 && g_picker_target<g_edit.count)g_edit.levels[g_picker_target].ink=ink;
   else if(g_picker_target==-5){for(int i=0;i<g_edit.count;i++)g_edit.levels[i].ink=ink;Status("All levels set to one colour. Apply or OK to keep it.");}
   else if(g_picker_target==-2)g_edit.fill_top=ink;
   else if(g_picker_target==-3)g_edit.fill_bottom=ink;
   else if(g_picker_target==-4)g_edit.base_color=ink;
   ClosePopup();g_dirty=true;g_ui_dirty=true;
  }
void Palette(const int target)
  {
   bool zone=target<=-1000;
   if(zone){if(!g_zeditor || -target-1000>=g_zedit.count)return;}
   else if(!g_editor || target>=g_edit.count || target<-5 || target==-1)return;
   if(target==-5 && g_edit.count==0){Status("Add a level first.");return;}
   ClosePopup();g_popup=3;g_picker_target=target;
   if(zone)g_pick_color=g_zedit.zones[-target-1000].ink;
   else if(target==-5)g_pick_color=g_edit.levels[0].ink;
   else g_pick_color=target>=0?g_edit.levels[target].ink:(target==-2?g_edit.fill_top:(target==-3?g_edit.fill_bottom:g_edit.base_color));
   RGBtoHSV(g_pick_color);
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(28);
   if(g_popup_y+U(365)>g_height)g_popup_y=(int)MathMax(4,g_height-U(365)-4);
   UIBase(Obj("P.BG"),OBJ_RECTANGLE_LABEL,g_popup_x,g_popup_y,U(360),U(354),"",clrWhiteSmoke,clrBlack,350);
   UIBase(Obj("P.Title"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(7),0,0,(zone?"Colour - "+Clip(g_zedit.zones[-target-1000].name,30):(target==-5?"One colour for every level":"All MT5 named colors + visual spectrum")),clrWhite,clrBlack,360);
   for(int i=0;i<ArraySize(g_palette);i++)
     {
      string n=Obj("P.Color"+IntegerToString(i));
      UIBase(n,OBJ_BUTTON,g_popup_x+U(10+(i%18)*19),g_popup_y+U(30+(i/18)*19),U(18),U(18),"",g_palette[i],clrBlack,360);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,g_color_names[i]);
     }
   g_picker_ready=g_picker.CreateBitmapLabel(0,0,Obj("P.Spectrum"),g_popup_x+U(12),g_popup_y+U(193),U(334),U(112),COLOR_FORMAT_ARGB_NORMALIZE);
   if(g_picker_ready)
     {string n=Obj("P.Spectrum");ObjectSetInteger(0,n,OBJPROP_ZORDER,370);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);ObjectSetString(0,n,OBJPROP_TOOLTIP,"\n");}
   UIBase(Obj("P.Sample"),OBJ_BUTTON,g_popup_x+U(12),g_popup_y+U(316),U(80),U(25),"",g_pick_color,clrBlack,370);
   UIBase(Obj("P.Use"),OBJ_BUTTON,g_popup_x+U(170),g_popup_y+U(316),U(85),U(25),"Use color",clrWhite,clrBlack,370);
   UIBase(Obj("P.Cancel"),OBJ_BUTTON,g_popup_x+U(259),g_popup_y+U(316),U(85),U(25),"Cancel",clrWhite,clrBlack,370);
   DrawPicker();
  }
void PickerMouse(const int x,const int y,const bool down,const bool was_down)
  {
   if(g_popup!=3 || !g_picker_ready){g_picker_drag=0;return;}
   int sx=g_popup_x+U(12),sy=g_popup_y+U(193),w=g_picker.Width(),h=g_picker.Height(),square=w-U(34);
   if(down && !was_down && x>=sx && x<sx+w && y>=sy && y<sy+h)g_picker_drag=(x<sx+square)?1:2;
   if(!down){g_picker_drag=0;return;}
   if(g_picker_drag==1){g_saturation=(double)Lim(x-sx,0,square-1)/(square-1);g_value=1.0-(double)Lim(y-sy,0,h-1)/(h-1);}
   else if(g_picker_drag==2)g_hue=(double)Lim(y-sy,0,h-1)/(h-1)*359.99;
   else return;
   g_pick_color=FPHSV(g_hue,g_saturation,g_value);DrawPicker();
  }
// Opacity slider: press anywhere on the track or thumb and drag; the number field,
// the thumb and the live fill preview follow the pointer.
void SliderMouse(const int x,const int y,const bool down,const bool was_down)
  {
   bool active=(g_editor && g_tab==4) || (g_zeditor && g_ztab==2);
   if(!active || g_hidden || !g_slider_on || g_popup!=0){g_slider_drag=false;return;}
   if(down && !was_down && x>=g_slider_x0-U(6) && x<=g_slider_x1+U(6) && y>=g_slider_y0 && y<=g_slider_y1)g_slider_drag=true;
   if(!down){g_slider_drag=false;return;}
   if(!g_slider_drag)return;
   int value=Lim((int)MathRound(100.0*(x-g_slider_x0)/MathMax(1,g_slider_x1-g_slider_x0)),0,100);
   if(value==(g_zeditor?g_zedit.opacity:g_edit.opacity))return;
   if(g_zeditor){g_zedit.opacity=value;SetText(UIS("Z.Opacity"),IntegerToString(value));ZonePreview(false);}
   else {g_edit.opacity=value;SetText(UIS("E.Opacity"),IntegerToString(value));g_dirty=true;}
   PlaceOpacityThumb();
  }

void CanvasObject(const string name,const bool back,const int z)
  {
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);ObjectSetInteger(0,name,OBJPROP_BACK,back);ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
  }
void DestroyTip()
  {if(g_tip_ready){g_tip.Destroy();g_tip_ready=false;}g_tip_visible=false;g_tip_key="";g_tip_x=FP_OFF;g_tip_y=FP_OFF;}
bool EnsureCanvases()
  {
   if(g_width<2 || g_height<2)return false;
   if(g_canvas_ready && g_line_canvas.Width()==g_width && g_line_canvas.Height()==g_height)return true;
   if(g_editor)HarvestEdits();
   g_fill_canvas.Destroy();g_line_canvas.Destroy();g_canvas_ready=false;g_fill_sig=0;
   if(!g_fill_canvas.CreateBitmapLabel(0,0,Obj("Fill"),0,0,g_width,g_height,COLOR_FORMAT_ARGB_NORMALIZE))return false;
   if(!g_line_canvas.CreateBitmapLabel(0,0,Obj("Lines"),0,0,g_width,g_height,COLOR_FORMAT_ARGB_NORMALIZE)){g_fill_canvas.Destroy();return false;}
   g_fill_canvas.Erase(0);g_fill_canvas.Update(false); // Initial transparent resource.
   CanvasObject(Obj("Fill"),true,0);CanvasObject(Obj("Lines"),false,0);
   g_line_canvas.FontSet("Segoe UI",U(15));g_canvas_ready=true;
   // Objects created later are painted on top. Re-create the native UI and the hover
   // tip after a new full-chart bitmap so drawings never cover the controls.
   RegDeletePrefix(UIS(""));ClosePopup();DestroyTip();g_status_shown=false;g_ui_dirty=true;
   return true;
  }
void HLine(const int x0,const int x1,const int y,const color ink,const int width,const int style,const uchar alpha=255)
  {
   if(y<0 || y>=g_height || x1<0 || x0>=g_width)return;
   int l=Lim(x0,0,g_width-1),r=Lim(x1,0,g_width-1),top=Lim(y-(width-1)/2,0,g_height-1),bottom=Lim(top+width-1,0,g_height-1);
   if(l>r)return;
   uint argb=ColorToARGB(ink,alpha);
   if(style==STYLE_SOLID){g_line_canvas.FillRectangle(l,top,r,bottom,argb);return;}
   // Preserve pattern phase as a finite extent moves off-screen.
   int cycle=0,parts=style==3?4:(style==4?6:2);
   for(int k=0;k<parts;k++)cycle+=FPPatternLength(style,k,width);
   int phase=(int)(((long)l-(long)x0)%cycle),part=0;
   while(phase>=FPPatternLength(style,part,width)){phase-=FPPatternLength(style,part,width);part++;}
   int pos=l;
   while(pos<=r)
     {int length=FPPatternLength(style,part,width)-phase;
      if(part%2==0)g_line_canvas.FillRectangle(pos,top,(int)MathMin(r,pos+length-1),bottom,argb);
      pos+=length;part=(part+1)%parts;phase=0;}
  }
void Diagonal(const int xa,const int ya,const int xb,const int yb,const color ink)
  {
   double x0=xa,y0=ya,x1=xb,y1=yb;
   if(!FPClip(x0,y0,x1,y1,g_width,g_height))return;
   double dx=x1-x0,dy=y1-y0;int length=(int)MathMax(1,MathMax(MathAbs(dx),MathAbs(dy)));
   uint argb=ColorToARGB(ink);
   for(int i=0;i<=length;i+=6)
     {double a=(double)i/length,b=(double)MathMin(length,i+2)/length;
      g_line_canvas.Line((int)MathRound(x0+dx*a),(int)MathRound(y0+dy*a),(int)MathRound(x0+dx*b),(int)MathRound(y0+dy*b),argb);}
  }
void Grip(const int x,const int y,const color ink)
  {
   if(x<0 || x>=g_width || y<0 || y>=g_height)return;
   g_line_canvas.FillRectangle(Lim(x-1,0,g_width-1),Lim(y-1,0,g_height-1),Lim(x+1,0,g_width-1),Lim(y+1,0,g_height-1),ColorToARGB(ink));
  }
void OriginGrip(const int x,const int y,const color ink)
  {
   if(x<0 || x>=g_width || y<0 || y>=g_height)return;
   g_line_canvas.FillRectangle(Lim(x-3,0,g_width-1),Lim(y-3,0,g_height-1),Lim(x+3,0,g_width-1),Lim(y+3,0,g_height-1),ColorToARGB(ink));
   g_line_canvas.FillRectangle(Lim(x-1,0,g_width-1),Lim(y-1,0,g_height-1),Lim(x+1,0,g_width-1),Lim(y+1,0,g_height-1),ColorToARGB(g_chart_bg));
  }
string LevelText(FPLevel &level,const double price)
  {string s=level.description;StringReplace(s,"%%",DoubleToString(level.value*100,1));StringReplace(s,"%$",DoubleToString(price,_Digits));return s;}
int OriginX(const int slot){return Lim(g_geo[slot].xl,3,g_width-4);}
// One projection per drawing per frame, shared by rendering, selection and hover.
void ComputeGeo(FPSetup &s,const int slot)
  {
   g_geo[slot].valid=false;g_geo[slot].count=0;g_geo[slot].line=-1;
   if(!Visible(s))return;
   // Drawings entirely outside the visible time window need no projection or raster work.
   if(g_cull_ok)
     {
      long lo=(long)MathMin(MathMin((double)s.left,(double)s.ta),(double)s.tb),hi=(long)MathMax(MathMax((double)s.right,(double)s.ta),(double)s.tb);
      if(!s.ray_right && hi<(long)g_vt0)return;
      if(!s.ray_left && lo>(long)g_vt1)return;
     }
   int xa=0,ya=0,xb=0,yb=0,xl=0,xr=0;
   if(!Geometry(s,xa,ya,xb,yb,xl,xr))return;
   g_geo[slot].valid=true;
   g_geo[slot].xa=xa;g_geo[slot].ya=ya;g_geo[slot].xb=xb;g_geo[slot].yb=yb;g_geo[slot].xl=xl;g_geo[slot].xr=xr;
   g_geo[slot].l=s.ray_left?0:xl;g_geo[slot].r=s.ray_right?g_width-1:xr;
   g_geo[slot].count=s.count;
   for(int i=0;i<s.count;i++)
     {
      g_geo[slot].ly[i]=FP_OFF;
      if(!s.levels[i].enabled)continue;
      int ignore=0,y=0;
      if(XY(s.ta,FPLevelPrice(s.pa,s.pb,s.levels[i].value),ignore,y))g_geo[slot].ly[i]=y;
     }
   if(s.hline)g_geo[slot].line=LineLevel(s);
  }
void ComputeAllGeo()
  {
   for(int i=0;i<g_count;i++)
     {if(g_editor && i==g_selected)ComputeGeo(g_edit,i);else ComputeGeo(g_sets[i],i);}
  }
bool FillRect(FPSetup &s,const int slot,int &x0,int &y0,int &x1,int &y1,int &top,int &bottom)
  {
   if(!g_geo[slot].valid || !s.fill || s.opacity<=0)return false;
   int fl=s.fill_rays?g_geo[slot].l:g_geo[slot].xl,fr=s.fill_rays?g_geo[slot].r:g_geo[slot].xr;
   top=(int)MathMin(g_geo[slot].ya,g_geo[slot].yb);bottom=(int)MathMax(g_geo[slot].ya,g_geo[slot].yb);
   if(fr<0 || fl>=g_width || bottom<0 || top>=g_height)return false;
   x0=Lim(fl,0,g_width-1);x1=Lim(fr,0,g_width-1);y0=Lim(top,0,g_height-1);y1=Lim(bottom,0,g_height-1);
   return x0<=x1;
  }
ulong FillSignatureOf(FPSetup &s,const int slot,ulong hash)
  {
   int x0=0,y0=0,x1=0,y1=0,top=0,bottom=0;
   if(!FillRect(s,slot,x0,y0,x1,y1,top,bottom))return hash;
   hash=FPMix(hash,slot);hash=FPMix(hash,x0);hash=FPMix(hash,y0);hash=FPMix(hash,x1);hash=FPMix(hash,y1);
   hash=FPMix(hash,top);hash=FPMix(hash,bottom);hash=FPMix(hash,(long)s.fill_top);hash=FPMix(hash,(long)s.fill_bottom);
   hash=FPMix(hash,s.gradient?1:0);hash=FPMix(hash,s.opacity);hash=FPMix(hash,(long)s.source_tf);
   return hash;
  }
void DrawLabel(FPSetup &s,const int slot,const int i,const int y)
  {
   double price=FPLevelPrice(s.pa,s.pb,s.levels[i].value);
   string text=LevelText(s.levels[i],price);
   if(StringLen(text)==0)return;
   int tw=g_line_canvas.TextWidth(text),th=g_line_canvas.TextHeight(text),half=(s.levels[i].width-1)/2;
   int tx=FPLabelX(g_geo[slot].xl,g_geo[slot].xr,g_geo[slot].l,g_geo[slot].r,tw,g_width,s.label_h,s.ray_left,s.ray_right,s.label_float,U(3));
   if(tx>=g_width || tx+tw<=0)return;
   int ty=s.label_v==1?y+(s.levels[i].width-half)+1:y-half-th-2;
   ty=Lim(ty,0,(int)MathMax(0,g_height-th));
   g_line_canvas.TextOut(tx,ty,text,ColorToARGB(s.levels[i].ink));
  }
void DrawSetup(FPSetup &s,const int slot,const bool selected)
  {
   if(!g_geo[slot].valid)return;
   int l=g_geo[slot].l,r=g_geo[slot].r;
   for(int i=0;i<s.count;i++)
     {
      int y=g_geo[slot].ly[i];
      if(y==FP_OFF || y<0 || y>=g_height)continue;
      HLine(l,r,y,s.levels[i].ink,s.levels[i].width,s.levels[i].style);
      if(s.labels && r>=0 && l<g_width)DrawLabel(s,slot,i,y);
     }
   int xa=g_geo[slot].xa,ya=g_geo[slot].ya,xb=g_geo[slot].xb,yb=g_geo[slot].yb;
   if(s.diagonal)Diagonal(xa,ya,xb,yb,s.base_color);
   if(!selected)return;
   int line=g_geo[slot].line;
   if(s.hline && line>=0 && g_geo[slot].ly[line]!=FP_OFF)
     {
      int y=g_geo[slot].ly[line];
      OriginGrip(OriginX(slot),y,s.anchors_locked?clrGray:s.levels[line].ink);
      if(!s.ray_right)Grip(Lim(g_geo[slot].xr,5,g_width-6),y,s.base_color);
      return;
     }
   color ink=s.anchors_locked?clrGray:s.base_color;
   Grip(xa,ya,ink);Grip(xb,yb,ink);Grip((int)(((long)xa+xb)/2),(int)(((long)ya+yb)/2),ink);
   int mid=Lim((int)(((long)ya+yb)/2),5,g_height-6);
   Grip(Lim(g_geo[slot].xl,5,g_width-6),mid,s.base_color);Grip(Lim(g_geo[slot].xr,5,g_width-6),mid,s.base_color);
  }
void Render()
  {
   ulong now=GetTickCount64();
   if(now<g_render_retry_after)return;
   if(!EnsureCanvases())
     {g_render_retry_after=now+250;Status("Canvas creation failed; retrying. Check chart size/memory.");return;}
   g_render_retry_after=0;
   ComputeAllGeo();
   ZonesPrepare();
   bool sel=g_selected>=0 && g_selected<g_count;
   // The fill layer is re-uploaded only when its pixels would actually change
   // (each upload copies a full chart-sized bitmap to the terminal).
   ulong sig=FPMix(FPMix(FPMix((ulong)1469598103934665603,g_width),g_height),sel?g_selected:-1);
   for(int i=0;i<g_count;i++)
     {if(sel && g_editor && i==g_selected)sig=FillSignatureOf(g_edit,i,sig);else sig=FillSignatureOf(g_sets[i],i,sig);}
   sig=FPMix(FPMix(FPMix(sig,(long)g_zfill_sig),g_zact.cut),g_zact.fib_lower);
   if(sig!=g_fill_sig)
     {
      // Fib and zone shading blended in one pass, so neither wipes out the other.
      g_fill_canvas.Erase(0);
      ShadeDraw(sel);
      g_fill_canvas.Update(false);g_fill_sig=sig;
     }
   g_line_canvas.Erase(0);
   ZonesDraw();
   // Unselected first, selected last for predictable selection and stacking.
   for(int i=0;i<g_count;i++)if(i!=g_selected)DrawSetup(g_sets[i],i,false);
   if(sel){if(g_editor)DrawSetup(g_edit,g_selected,true);else DrawSetup(g_sets[g_selected],g_selected,true);}
   g_line_canvas.Update(false);g_dirty=false;
   g_hover_pending=true; // Geometry moved under a resting pointer.
  }
bool ViewChanged()
  {
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0),h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   long first=ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR),scale=ChartGetInteger(0,CHART_SCALE),bars=ChartGetInteger(0,CHART_VISIBLE_BARS);
   double lo=ChartGetDouble(0,CHART_PRICE_MIN,0),hi=ChartGetDouble(0,CHART_PRICE_MAX,0);
   datetime first_time=iTime(_Symbol,PERIOD_CURRENT,(int)first);
   bool changed=(w!=g_width || h!=g_height || first!=g_view_first || first_time!=g_view_time || scale!=g_view_scale || bars!=g_view_bars || lo!=g_view_min || hi!=g_view_max);
   if(w!=g_width || h!=g_height)
     {
      if(g_editor)HarvestEdits();
      g_width=w;g_height=h;g_scale=MathMax(.75,MathMin(2.0,InpUIScale));
      // Keep the compact desktop panel within the chart where practical.
      if(g_width>30)g_scale=MathMin(g_scale,MathMax(.75,(g_width-24)/(double)(FPZ_PANEL_WIDTH+20)));
      g_rows=Lim((int)((g_height-U(280))/U(24)),6,10);g_panel_x=U(12);g_panel_y=U(94);
      g_list_rows=Lim((int)((g_height-U(270))/U(24)),5,15);
      g_toolbar_x=Lim(U(g_toolbar_lx),0,(int)MathMax(0,g_width-U(FP_TOOLBAR_WIDTH)));
      g_toolbar_y=Lim(U(g_toolbar_ly),0,(int)MathMax(0,g_height-U(FP_TOOLBAR_HEIGHT)));
      g_ui_dirty=true;
      if(g_editor){ClosePopup();g_ui_dirty=true;}
     }
   if(changed)
     {
      // Visible time window for culling. When the right edge reaches the newest bar the
      // window is open-ended, so drawings in the future area are never culled.
      datetime t0=0,t1=0;double p=0;int sub=-1;
      g_cull_ok=w>2 && ChartXYToTimePrice(0,0,h/2,sub,t0,p) && sub==0 && ChartXYToTimePrice(0,w-1,h/2,sub,t1,p) && sub==0 && t1>t0;
      if(g_cull_ok)
        {
         long period=PeriodSeconds();
         g_vt0=(datetime)((long)t0-2*period);
         g_vt1=(t1>=iTime(_Symbol,PERIOD_CURRENT,0))?FP_FAR_FUTURE:(datetime)((long)t1+2*period);
        }
     }
   g_view_first=first;g_view_time=first_time;g_view_scale=scale;g_view_bars=bars;g_view_min=lo;g_view_max=hi;
   return changed;
  }

// ------------------------------------------------------------------ drawings list
// Searchable, filterable, sortable manager for up to 1000 drawings. Row clicks select,
// double-click opens Properties; per-row buttons toggle visibility on this timeframe,
// scroll the chart to the drawing, edit or delete it (two-step).
int ListHeight(){return U(156+g_list_rows*24);}
double ListPrice(FPSetup &s)
  {int line=LineLevel(s);return (s.hline && line>=0)?FPLevelPrice(s.pa,s.pb,s.levels[line].value):s.pa;}
string ListPriceText(FPSetup &s)
  {
   if(s.hline)return DoubleToString(ListPrice(s),_Digits);
   return DoubleToString(s.pb,_Digits)+" "+Glyph(0x2192)+" "+DoubleToString(s.pa,_Digits);
  }
color ListInk(FPSetup &s)
  {int line=LineLevel(s);return line>=0?s.levels[line].ink:s.base_color;}
bool ListLess(const int a,const int b)
  {
   int c=0;
   if(g_list_sort==1)c=StringCompare(g_sets[a].name,g_sets[b].name,false);
   else if(g_list_sort==2)c=(g_sets[a].hline?1:0)-(g_sets[b].hline?1:0);
   else if(g_list_sort==3)c=TFIndex(g_sets[a].source_tf)-TFIndex(g_sets[b].source_tf);
   else if(g_list_sort==4){double pa=ListPrice(g_sets[a]),pb=ListPrice(g_sets[b]);c=pa<pb?-1:(pa>pb?1:0);}
   if(c==0)c=g_sets[a].uid-g_sets[b].uid;
   return g_list_desc?c>0:c<0;
  }
bool ListMatch(const int i,const string needle)
  {
   if(g_list_filter==1 && !Visible(g_sets[i]))return false;
   if(g_list_filter==2 && g_sets[i].hline)return false;
   if(g_list_filter==3 && !g_sets[i].hline)return false;
   if(StringLen(needle)==0)return true;
   string hay=g_sets[i].name+" "+g_sets[i].description;
   StringToLower(hay);
   return StringFind(hay,needle)>=0;
  }
// Filtered + sorted index, rebuilt only when drawings or list settings changed.
void ListRebuild()
  {
   string key=IntegerToString(g_save_gen)+"|"+IntegerToString(g_count)+"|"+IntegerToString(g_list_filter)+"|"+IntegerToString(g_list_sort)+"|"+(g_list_desc?"d":"a")+"|"+g_list_search+"|"+IntegerToString(g_tf);
   if(key==g_list_key)return;
   g_list_key=key;
   string needle=g_list_search;StringTrimLeft(needle);StringTrimRight(needle);StringToLower(needle);
   g_list_n=0;
   for(int i=0;i<g_count;i++)if(ListMatch(i,needle))g_list_idx[g_list_n++]=i;
   // Shell sort: no recursion, fast enough for 1000 rows.
   for(int gap=g_list_n/2;gap>0;gap/=2)
      for(int i=gap;i<g_list_n;i++)
        {
         int v=g_list_idx[i],j=i;
         while(j>=gap && ListLess(v,g_list_idx[j-gap])){g_list_idx[j]=g_list_idx[j-gap];j-=gap;}
         g_list_idx[j]=v;
        }
  }
color ListRowColor(const int r)
  {
   int slot=g_list_rowslot[r];
   if(slot>=0 && slot==g_selected)return clrLightSteelBlue;
   if(r==g_list_hover)return clrLavender;
   return r%2==0?clrWhite:clrWhiteSmoke;
  }
void SetBg(const string name,const color bg)
  {int i=RegFind(name);if(i<0 || g_reg[i].bg==(int)bg)return;ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);g_reg[i].bg=(int)bg;}
void BuildList()
  {
   ListRebuild();
   int rows=g_list_rows,pages=(int)MathMax(1,(g_list_n+rows-1)/rows);
   if(g_list_follow && g_selected>=0)
     {for(int i=0;i<g_list_n;i++)if(g_list_idx[i]==g_selected){g_list_page=i/rows;break;}}
   g_list_follow=false;
   g_list_page=Lim(g_list_page,0,pages-1);
   int x=g_panel_x,y=g_panel_y;
   Box("L.Background",x,y,FP_LIST_WIDTH,156+rows*24,clrWhiteSmoke);
   Label("L.Title","Drawings   "+IntegerToString(g_count)+" / "+IntegerToString(MaxSetups()),x+U(10),y+U(7));
   Button("L.Close",Glyph(0xD7),x+U(FP_LIST_WIDTH-28),y+U(4),22,20);
   Tooltip("L.Close","Close the list (Esc)");
   // Search
   Label("L.SearchL","Search",x+U(10),y+U(34));
   Edit("L.Search",g_list_search,x+U(60),y+U(30),300);
   Tooltip("L.Search","Name or description; press Enter");
   Button("L.Find","Find",x+U(364),y+U(30),70);Button("L.Clear","Clear",x+U(438),y+U(30),70);
   // Filter (segmented) and bulk visibility
   string filters[]={"All","This TF","Fibs","Lines"};int fw[]={44,64,46,50};int fx=x+U(10);
   for(int i=0;i<4;i++){Button("L.F"+IntegerToString(i),filters[i],fx,y+U(58),fw[i],22,i==g_list_filter?clrLightSteelBlue:clrWhite);fx+=U(fw[i]+2);}
   Button("L.ShowAll","Show all here",x+U(300),y+U(58),104);Button("L.HideAll","Hide all here",x+U(406),y+U(58),104);
   Tooltip("L.ShowAll","Show every listed drawing on "+g_tf_names[g_tf]);Tooltip("L.HideAll","Hide every listed drawing on "+g_tf_names[g_tf]);
   // Sortable column headers
   string heads[]={"#","Name","Type","TF","Price"};int hx[]={6,26,204,240,276};int hw[]={18,176,34,34,126};
   for(int i=0;i<5;i++)
     {
      string text=heads[i];
      if(g_list_sort==i)text+=" "+Glyph(g_list_desc?0x25BC:0x25B2);
      Button("L.S"+IntegerToString(i),text,x+U(hx[i]),y+U(86),hw[i],22,g_list_sort==i?clrGainsboro:clrWhiteSmoke);
     }
   Tooltip("L.S0","Creation order");
   Label("L.HHere","Here",x+U(406),y+U(90));
   // Rows
   int first=g_list_page*rows;
   for(int r=0;r<rows;r++)
     {
      int i=first+r,ry=y+U(112+r*24);string n=IntegerToString(r);
      g_list_rowslot[r]=i<g_list_n?g_list_idx[i]:-1;
      if(i>=g_list_n)continue;
      int slot=g_list_idx[i];
      Box("L.Row"+n,x+U(6),ry,FP_LIST_WIDTH-12,22,ListRowColor(r));
      Box("L.Sw"+n,x+U(12),ry+U(5),12,12,ListInk(g_sets[slot]));
      Label("L.Name"+n,Clip(g_sets[slot].name,30),x+U(30),ry+U(4));
      Label("L.Type"+n,g_sets[slot].hline?"Line":"Fib",x+U(206),ry+U(4),clrDimGray);
      int tf=TFIndex(g_sets[slot].source_tf);
      Label("L.TF"+n,tf>=0?g_tf_names[tf]:"?",x+U(242),ry+U(4),clrDimGray);
      Label("L.Price"+n,ListPriceText(g_sets[slot]),x+U(278),ry+U(4),clrDimGray);
      bool here=Visible(g_sets[slot]);
      Button("L.Here"+n,Glyph(here?0x25CF:0x25CB),x+U(406),ry+U(1),24,20,here?clrHoneydew:clrWhite);
      Tooltip("L.Here"+n,(here?"Hide on ":"Show on ")+g_tf_names[g_tf]);
      Button("L.Go"+n,"Go",x+U(432),ry+U(1),28,20);Tooltip("L.Go"+n,"Scroll the chart to this drawing");
      Button("L.Edit"+n,"Edit",x+U(462),ry+U(1),30,20);
      bool arm=g_list_confirm==g_sets[slot].uid && GetTickCount64()<g_list_confirm_until;
      Button("L.Del"+n,Glyph(0xD7),x+U(494),ry+U(1),20,20,arm?clrRed:clrWhite);
      Tooltip("L.Del"+n,arm?"Click again to delete":"Delete");
     }
   if(g_list_n==0)
      Label("L.Empty",g_count==0?"No drawings yet. Click New Fib to draw one.":"No drawings match the search or filter.",x+U(16),y+U(120),clrDimGray);
   // Footer
   int fy=y+U(156+rows*24)-U(32);
   string info=g_list_n==0?"":"Showing "+IntegerToString(first+1)+"-"+IntegerToString((int)MathMin(g_list_n,first+rows))+" of "+IntegerToString(g_list_n);
   if(g_list_n<g_count){if(StringLen(info)>0)info+="  ";info+="(filtered from "+IntegerToString(g_count)+")";}
   Label("L.Info",info,x+U(10),fy+U(4),clrDimGray);
   Button("L.Prev","<",x+U(400),fy,26);
   Label("L.Page",IntegerToString(g_list_page+1)+" / "+IntegerToString(pages),x+U(432),fy+U(4));
   Button("L.Next",">",x+U(484),fy,26);
  }
// Row under the pointer; `full` includes the action buttons column.
int ListRowAt(const int x,const int y,const bool full)
  {
   if(!g_list || g_editor || g_hidden)return -1;
   if(x<g_panel_x+U(6) || x>g_panel_x+U(full?FP_LIST_WIDTH-6:400))return -1;
   double uy=(y-g_panel_y)/g_scale-112;
   if(uy<0)return -1;
   int r=(int)(uy/24);
   if(r>=g_list_rows || uy-r*24>22 || g_list_rowslot[r]<0)return -1;
   return r;
  }
void ListHover(const int r)
  {
   if(r==g_list_hover)return;
   int old=g_list_hover;g_list_hover=r;
   if(old>=0 && old<g_list_rows)SetBg(UIS("L.Row"+IntegerToString(old)),ListRowColor(old));
   if(r>=0)SetBg(UIS("L.Row"+IntegerToString(r)),ListRowColor(r));
   g_need_redraw=true;
  }
void ListMouse(const int x,const int y,const bool down,const bool was_down)
  {
   if(!g_list || g_editor || g_hidden || g_popup!=0){g_list_hover=-1;return;}
   if(!down){ListHover(ListRowAt(x,y,true));return;}
   if(was_down)return;
   int r=ListRowAt(x,y,false);
   if(r<0)return;
   int slot=g_list_rowslot[r];
   ulong now=GetTickCount64();
   if(slot==g_list_last_slot && now-g_list_last_click<400)
     {g_list_last_click=0;g_selected=slot;g_list=false;g_dirty=true;OpenEditor();return;}
   g_list_last_slot=slot;g_list_last_click=now;
   if(g_selected!=slot){g_selected=slot;g_dirty=true;g_ui_dirty=true;}
  }
void ListWheel(const int x,const int y,const int delta)
  {
   if(!g_list || g_editor || g_hidden || delta==0)return;
   if(x<g_panel_x || x>g_panel_x+U(FP_LIST_WIDTH) || y<g_panel_y || y>g_panel_y+ListHeight())return;
   int pages=(int)MathMax(1,(g_list_n+g_list_rows-1)/g_list_rows),page=Lim(g_list_page+(delta>0?-1:1),0,pages-1);
   if(page!=g_list_page){g_list_page=page;g_list_hover=-1;g_ui_dirty=true;}
  }
void ToggleList()
  {
   if(g_list){g_list=false;g_ui_dirty=true;return;}
   if(g_editor){Status("Finish or cancel Properties first.");return;}
   if(g_zeditor){Status("Close the Zones window first.");return;}
   ClosePopup();g_list=true;g_list_follow=true;g_list_hover=-1;g_list_key="";g_ui_dirty=true;
  }
// Scroll the chart so the drawing is centred, and select it.
void GoTo(const int slot)
  {
   if(slot<0 || slot>=g_count)return;
   datetime target=g_sets[slot].hline?g_sets[slot].left:(datetime)(((long)g_sets[slot].ta+(long)g_sets[slot].tb)/2);
   int shift=iBarShift(_Symbol,PERIOD_CURRENT,target,false);
   if(shift<0){Status("No chart history at "+TimeToString(target)+".");return;}
   int visible=(int)ChartGetInteger(0,CHART_VISIBLE_BARS);
   ChartSetInteger(0,CHART_AUTOSCROLL,false);
   ChartNavigate(0,CHART_END,-(int)MathMax(0,shift-visible/2));
   g_selected=slot;g_dirty=true;g_ui_dirty=true;g_view_probe=true;g_fast_view_until=GetTickCount64()+300;
   if(Visible(g_sets[slot]))Status("Showing "+g_sets[slot].name+".");
   else Status(g_sets[slot].name+" is hidden on "+g_tf_names[g_tf]+"; use its "+Glyph(0x25CB)+" button to show it here.");
  }
void SetHere(const int slot,const bool on)
  {
   if(on)g_sets[slot].visible_mask|=(long)1<<g_tf;else g_sets[slot].visible_mask&=~((long)1<<g_tf);
   g_sets[slot].visibility_mode=0;
  }
void ListToggleHere(const int slot)
  {
   if(slot<0 || slot>=g_count)return;
   long before=g_sets[slot].visible_mask;int mode=g_sets[slot].visibility_mode;
   SetHere(slot,!Visible(g_sets[slot]));
   if(!Save()){g_sets[slot].visible_mask=before;g_sets[slot].visibility_mode=mode;return;}
   g_dirty=true;g_ui_dirty=true;
   Status(g_sets[slot].name+(Visible(g_sets[slot])?" shown on ":" hidden on ")+g_tf_names[g_tf]+".");
  }
void ListBulkHere(const bool on)
  {
   if(g_list_n==0)return;
   long masks[];int modes[];ArrayResize(masks,g_list_n);ArrayResize(modes,g_list_n);
   for(int i=0;i<g_list_n;i++){int s=g_list_idx[i];masks[i]=g_sets[s].visible_mask;modes[i]=g_sets[s].visibility_mode;SetHere(s,on);}
   if(!Save())
     {for(int i=0;i<g_list_n;i++){int s=g_list_idx[i];g_sets[s].visible_mask=masks[i];g_sets[s].visibility_mode=modes[i];}return;}
   g_dirty=true;g_ui_dirty=true;
   Status(IntegerToString(g_list_n)+" drawing(s) "+(on?"shown on ":"hidden on ")+g_tf_names[g_tf]+".");
  }
void ListDelete(const int slot)
  {
   if(slot<0 || slot>=g_count)return;
   ulong now=GetTickCount64();
   if(g_list_confirm!=g_sets[slot].uid || now>g_list_confirm_until)
     {
      g_list_confirm=g_sets[slot].uid;g_list_confirm_until=now+4000;g_ui_dirty=true;
      Status("Click "+Glyph(0xD7)+" again to delete "+g_sets[slot].name+".");return;
     }
   g_list_confirm=-1;
   RemoveAt(slot);
  }
void ListClick(const string key)
  {
   if(key=="L.Close"){g_list=false;g_ui_dirty=true;return;}
   if(key=="L.Find"){g_list_search=ObjectGetString(0,UIS("L.Search"),OBJPROP_TEXT);g_list_page=0;g_ui_dirty=true;return;}
   if(key=="L.Clear"){g_list_search="";g_list_page=0;g_ui_dirty=true;return;}
   if(key=="L.Prev"){g_list_page=(int)MathMax(0,g_list_page-1);g_list_hover=-1;g_ui_dirty=true;return;}
   if(key=="L.Next"){g_list_page++;g_list_hover=-1;g_ui_dirty=true;return;}
   if(key=="L.ShowAll"){ListBulkHere(true);return;}
   if(key=="L.HideAll"){ListBulkHere(false);return;}
   if(StringFind(key,"L.F")==0){g_list_filter=Lim((int)StringToInteger(StringSubstr(key,3)),0,3);g_list_page=0;g_ui_dirty=true;return;}
   if(StringFind(key,"L.S")==0 && StringLen(key)==4)
     {
      int sort=Lim((int)StringToInteger(StringSubstr(key,3)),0,4);
      if(sort==g_list_sort)g_list_desc=!g_list_desc;else {g_list_sort=sort;g_list_desc=(sort==0);}
      g_list_page=0;g_ui_dirty=true;return;
     }
   string actions[]={"L.Here","L.Go","L.Edit","L.Del"};
   for(int a=0;a<4;a++)
     {
      if(StringFind(key,actions[a])!=0)continue;
      int r=(int)StringToInteger(StringSubstr(key,StringLen(actions[a])));
      if(r<0 || r>=g_list_rows)return;
      int slot=g_list_rowslot[r];
      if(slot<0 || slot>=g_count)return;
      if(a==0)ListToggleHere(slot);
      else if(a==1)GoTo(slot);
      else if(a==2){g_selected=slot;g_list=false;g_dirty=true;OpenEditor();}
      else ListDelete(slot);
      return;
     }
  }

// ------------------------------------------------------------------ sessions, killzones & macros
// Zones are defined in New York wall-clock time (the ICT convention) and converted to the
// broker's server clock per date, so daylight-saving changes on either side stay exact.
// Calendar helpers work on days since 1970-01-01 (proleptic Gregorian, H. Hinnant).
long FPFloorDiv(const long a,const long b)
  {long q=a/b;if(a%b!=0 && ((a<0)!=(b<0)))q--;return q;}
long FPDaysFromCivil(int y,const int m,const int d)
  {
   y-=m<=2?1:0;
   long era=(y>=0?y:y-399)/400;
   long yoe=y-era*400;
   long doy=(153*(m+(m>2?-3:9))+2)/5+d-1;
   long doe=yoe*365+yoe/4-yoe/100+doy;
   return era*146097+doe-719468;
  }
void FPCivilFromDays(long z,int &y,int &m,int &d)
  {
   z+=719468;
   long era=(z>=0?z:z-146096)/146097;
   long doe=z-era*146097;
   long yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   long doy=doe-(365*yoe+yoe/4-yoe/100);
   long mp=(5*doy+2)/153;
   d=(int)(doy-(153*mp+2)/5+1);
   m=(int)(mp<10?mp+3:mp-9);
   y=(int)(yoe+era*400+(m<=2?1:0));
  }
int FPDow(const long days){long w=(days+4)%7;if(w<0)w+=7;return (int)w;}   // 0 = Sunday
int FPDaysInMonth(const int y,const int m)
  {return (int)(FPDaysFromCivil(m==12?y+1:y,m==12?1:m+1,1)-FPDaysFromCivil(y,m,1));}
int FPNthSunday(const int y,const int m,const int n)
  {return 1+(7-FPDow(FPDaysFromCivil(y,m,1)))%7+7*(n-1);}
int FPLastSunday(const int y,const int m)
  {int last=FPDaysInMonth(y,m);return last-FPDow(FPDaysFromCivil(y,m,last));}
// New York daylight saving: second Sunday of March to first Sunday of November, 02:00 local.
bool FPNYDst(const long ny)
  {
   int y=0,m=0,d=0;FPCivilFromDays(FPFloorDiv(ny,86400),y,m,d);
   long start=FPDaysFromCivil(y,3,FPNthSunday(y,3,2))*86400+7200,stop=FPDaysFromCivil(y,11,FPNthSunday(y,11,1))*86400+7200;
   return ny>=start && ny<stop;
  }
bool FPUSDstUtc(const long utc)
  {
   int y=0,m=0,d=0;FPCivilFromDays(FPFloorDiv(utc,86400),y,m,d);
   long start=FPDaysFromCivil(y,3,FPNthSunday(y,3,2))*86400+7*3600,stop=FPDaysFromCivil(y,11,FPNthSunday(y,11,1))*86400+6*3600;
   return utc>=start && utc<stop;
  }
// European summer time: last Sunday of March to last Sunday of October, 01:00 UTC.
bool FPEUDst(const long utc)
  {
   int y=0,m=0,d=0;FPCivilFromDays(FPFloorDiv(utc,86400),y,m,d);
   long start=FPDaysFromCivil(y,3,FPLastSunday(y,3))*86400+3600,stop=FPDaysFromCivil(y,10,FPLastSunday(y,10))*86400+3600;
   return utc>=start && utc<stop;
  }
long FPNYToUtc(const long ny){return ny+(FPNYDst(ny)?4:5)*3600;}
long FPUtcToNY(const long utc){return utc-(FPUSDstUtc(utc)?4:5)*3600;}
// Seconds the broker's server clock is ahead of UTC.
// 1 = New York +7 h (most forex brokers), 2 = GMT+N, 3 = GMT+N with EU DST, 4 = GMT+N with US DST.
long FPServerOffset(const int mode,const int gmt,const long utc)
  {
   if(mode==1)return (FPUSDstUtc(utc)?3:2)*3600;
   if(mode==3)return ((long)gmt+(FPEUDst(utc)?1:0))*3600;
   if(mode==4)return ((long)gmt+(FPUSDstUtc(utc)?1:0))*3600;
   return (long)gmt*3600;
  }
long FPNYToServer(const long ny,const int mode,const int gmt)
  {long utc=FPNYToUtc(ny);return utc+FPServerOffset(mode,gmt,utc);}
long FPServerToNY(const long server,const int mode,const int gmt)
  {
   long utc=server-FPServerOffset(mode,gmt,server-(long)gmt*3600);
   utc=server-FPServerOffset(mode,gmt,utc);
   return FPUtcToNY(utc);
  }
// Trading day (days since 1970) of a New York moment: the forex day rolls at 17:00 New York.
long FPTradingDay(const long ny){return FPFloorDiv(ny+7*3600,86400);}
// Zones starting at 17:00 or later open on the previous calendar evening of their trading day.
long FPZoneNYStart(const long td,const int start){return (start>=1020?td-1:td)*86400+(long)start*60;}
long FPZoneNYEnd(const long ny_start,const int start,const int end)
  {
   if(end==start)return ny_start;
   long midnight=ny_start-(long)start*60;
   return end>start?midnight+(long)end*60:midnight+86400+(long)end*60;
  }
string FPTwo(const int v){string s=IntegerToString(v);return StringLen(s)<2?"0"+s:s;}
string FPHHMM(const int minutes){int m=((minutes%1440)+1440)%1440;return FPTwo(m/60)+":"+FPTwo(m%60);}
string FPDuration(const long seconds)
  {
   long m=(seconds+59)/60;
   if(m<60)return IntegerToString(m)+" min";
   return IntegerToString(m/60)+"h "+FPTwo((int)(m%60))+"m";
  }
// Accepts 9, 09, 930, 0930, 9:30, 09:30, 9.30 and 9h30; 24:00 means midnight.
bool FPParseHHMM(string text,int &minutes)
  {
   StringTrimLeft(text);StringTrimRight(text);
   StringReplace(text,".",":");StringReplace(text,"h",":");StringReplace(text,"H",":");
   int n=StringLen(text);
   if(n==0 || n>5)return false;
   int colon=StringFind(text,":");
   string hs,ms;
   if(colon>=0){hs=StringSubstr(text,0,colon);ms=StringSubstr(text,colon+1);}
   else if(n<=2){hs=text;ms="00";}
   else {hs=StringSubstr(text,0,n-2);ms=StringSubstr(text,n-2);}
   if(StringLen(hs)<1 || StringLen(hs)>2 || StringLen(ms)!=2)return false;
   string all=hs+ms;
   for(int i=0;i<StringLen(all);i++){ushort c=StringGetCharacter(all,i);if(c<'0' || c>'9')return false;}
   int h=(int)StringToInteger(hs),m=(int)StringToInteger(ms);
   if(h==24 && m==0)h=0;
   if(h>23 || m>59)return false;
   minutes=h*60+m;
   return true;
  }
string FPZGroupName(const int g)
  {
   if(g==0)return "Sessions";
   if(g==1)return "Killzones";
   if(g==2)return "Silver Bullet";
   if(g==3)return "Macros";
   return "Time lines";
  }
string FPZGroupSingular(const int g)
  {
   if(g==0)return "Session";
   if(g==1)return "Killzone";
   if(g==2)return "Silver Bullet";
   if(g==3)return "Macro";
   return "Time line";
  }
int FPZDuration(FPZone &z){if(z.end==z.start)return 0;return z.end>z.start?z.end-z.start:z.end+1440-z.start;}
void FPZoneSet(FPZone &z,const string name,const int start,const int end,const int group,const color ink,const bool on)
  {
   z.enabled=on;z.name=name;z.start=start;z.end=end;z.group=group;z.ink=ink;
   z.width=1;z.label=1;z.align=0;z.distance=6;z.height=16;z.mopacity=45;
   z.fill=false;z.box=false;z.extend=false;z.alert=false;z.open_line=0;z.midline=false;z.stack=0;
   if(group==0){z.style=5;z.marker=3;z.height=15;z.mopacity=35;z.distance=0;}       // sessions: strips along the chart bottom
   else if(group==1){z.style=2;z.marker=4;z.fill=true;z.distance=0;}                // killzones: shaded columns, label strip on top
   else if(group==2){z.style=0;z.marker=2;z.fill=true;}                             // silver bullet: above the window's high
   else if(group==3){z.style=2;z.marker=2;z.height=14;z.mopacity=40;}              // macros: dotted bounds, strip above the high
   else {z.style=1;z.marker=4;z.height=14;z.distance=0;}                           // time lines: dashed line, tag on top
  }
// The default list: ICT killzones, Silver Bullet windows, macros and time lines from the
// lecture, plus the seven sessions. `indices` switches to the index-futures selection.
void FPZoneDefaultList(FPZoneConfig &c,const bool indices)
  {
   int n=0;
   FPZoneSet(c.zones[n++],"Asian",1140,240,0,clrMediumPurple,true);
   FPZoneSet(c.zones[n++],"London",180,720,0,clrRoyalBlue,true);
   FPZoneSet(c.zones[n++],"New York",480,1020,0,clrSeaGreen,true);
   FPZoneSet(c.zones[n++],"London AM",180,420,0,clrCornflowerBlue,true);
   FPZoneSet(c.zones[n++],"London PM",420,720,0,clrSteelBlue,true);
   FPZoneSet(c.zones[n++],"New York AM",480,720,0,clrMediumSeaGreen,true);
   FPZoneSet(c.zones[n++],"New York PM",720,1020,0,clrDarkSeaGreen,true);
   FPZoneSet(c.zones[n++],"Asian KZ",1200,0,1,clrMediumOrchid,!indices);c.zones[n-1].box=true;c.zones[n-1].midline=true;c.zones[n-1].extend=true;
   FPZoneSet(c.zones[n++],"London KZ",120,300,1,clrDodgerBlue,true);
   FPZoneSet(c.zones[n++],"NY KZ",420,600,1,clrLimeGreen,!indices);
   FPZoneSet(c.zones[n++],"NY AM KZ (indices)",510,660,1,clrTeal,indices);
   FPZoneSet(c.zones[n++],"London Close KZ",600,720,1,clrOrange,!indices);
   FPZoneSet(c.zones[n++],"NY Lunch",720,780,1,clrGray,true);
   FPZoneSet(c.zones[n++],"NY PM KZ",810,960,1,clrGoldenrod,true);
   FPZoneSet(c.zones[n++],"CBDR",840,1200,1,clrSienna,false);c.zones[n-1].box=true;c.zones[n-1].midline=true;
   FPZoneSet(c.zones[n++],"NY Opening Range",570,600,1,clrDarkTurquoise,indices);c.zones[n-1].box=true;c.zones[n-1].midline=true;
   FPZoneSet(c.zones[n++],"Silver Bullet London",180,240,2,clrGold,true);
   FPZoneSet(c.zones[n++],"Silver Bullet AM",600,660,2,clrGold,true);
   FPZoneSet(c.zones[n++],"Silver Bullet PM",840,900,2,clrGold,true);
   int macros[]={153,180,243,270,530,550,590,610,650,670,710,730,790,820,915,945};
   for(int k=0;k<8;k++)FPZoneSet(c.zones[n++],"Macro "+FPHHMM(macros[2*k]),macros[2*k],macros[2*k+1],3,clrMediumVioletRed,true);
   FPZoneSet(c.zones[n++],"Midnight Open",0,0,4,clrCrimson,true);c.zones[n-1].open_line=2;
   FPZoneSet(c.zones[n++],"08:30 News",510,510,4,clrDimGray,true);
   FPZoneSet(c.zones[n++],"09:30 Equities Open",570,570,4,clrDimGray,true);
   FPZoneSet(c.zones[n++],"10:00 News",600,600,4,clrDimGray,false);
   FPZoneSet(c.zones[n++],"16:00 Close",960,960,4,clrDimGray,indices);
   FPZoneSet(c.zones[n++],"17:00 Rollover",1020,1020,4,clrDimGray,false);
   c.count=n;
  }
void FPZoneDefaults(FPZoneConfig &c,const bool indices)
  {
   c.enabled=true;
   for(int g=0;g<FPZ_GROUPS;g++)c.group_on[g]=true;
   c.group_on[2]=indices;                       // Silver Bullet windows are opt-in for forex
   c.group_tf[0]=11;c.group_tf[1]=11;c.group_tf[2]=8;c.group_tf[3]=4;c.group_tf[4]=10; // H1, H1, M15, M5, M30
   c.days_back=10;c.upcoming=true;c.dow_mask=62;c.broker_mode=0;c.broker_gmt=2;
   c.fill=true;c.fill_mode=0;c.opacity=8;c.gradient=false;c.fade_old=true;c.lines_full=true;
   c.declutter=true;c.highlight=true;c.hover=true;c.label_size=11;
   c.alert_sound=true;c.alert_push=true;c.alert_lead=0;
   c.cut=1;c.fib_lower=0;
   FPZoneDefaultList(c,indices);
  }
// Trading-day order: zones that open the previous evening (17:00 or later) come first.
int FPZSortKey(FPZone &z){return z.start>=1020?z.start-1440:z.start;}
void FPZSortByTime(FPZoneConfig &c)
  {
   for(int i=1;i<c.count;i++)
     {
      FPZone v=c.zones[i];int j=i;
      while(j>0)
        {
         int a=FPZSortKey(c.zones[j-1]),b=FPZSortKey(v);
         if(a<b || (a==b && FPZDuration(c.zones[j-1])>=FPZDuration(v)))break;
         c.zones[j]=c.zones[j-1];j--;
        }
      c.zones[j]=v;
     }
  }

// ---- zone settings files (shared per workspace) and presets
// The two Fib-shading settings live in spare bits of the settings flags (11-12 and 13-14).
// Versions 1.62 and 1.63 ignore those bits, so they can still read these files. A stored 0
// means the default (cut Half, Fib shading Full), as in files written by those versions.
int FPZCutStore(const int cut){return cut==1?0:(cut==0?1:2);}
int FPZCutLoad(const int v){return v==1?0:(v==2?2:1);}
void FPZWriteConfig(const int f,FPZoneConfig &c)
  {
   FileWriteInteger(f,FPZ_MAGIC);FileWriteInteger(f,FPZ_SCHEMA);
   int flags=(c.enabled?1:0)|(c.upcoming?2:0)|(c.fill?4:0)|(c.gradient?8:0)|(c.fade_old?16:0)|(c.lines_full?32:0)
             |(c.declutter?64:0)|(c.highlight?128:0)|(c.hover?256:0)|(c.alert_sound?512:0)|(c.alert_push?1024:0)
             |(FPZCutStore(c.cut)<<11)|(Lim(c.fib_lower,0,2)<<13);
   FileWriteInteger(f,flags);
   for(int g=0;g<FPZ_GROUPS;g++)FileWriteInteger(f,(c.group_on[g]?1:0)|(c.group_tf[g]<<1));
   FileWriteInteger(f,c.days_back);FileWriteInteger(f,c.dow_mask);FileWriteInteger(f,c.broker_mode);FileWriteInteger(f,c.broker_gmt);
   FileWriteInteger(f,c.fill_mode);FileWriteInteger(f,c.opacity);FileWriteInteger(f,c.label_size);FileWriteInteger(f,c.alert_lead);
   FileWriteInteger(f,c.count);
   for(int i=0;i<c.count;i++)
     {
      WText(f,c.zones[i].name);
      FileWriteInteger(f,c.zones[i].start);FileWriteInteger(f,c.zones[i].end);FileWriteInteger(f,c.zones[i].style);
      FileWriteInteger(f,c.zones[i].width);FileWriteInteger(f,(int)c.zones[i].ink);FileWriteInteger(f,c.zones[i].label);
      FileWriteInteger(f,c.zones[i].marker);FileWriteInteger(f,c.zones[i].align);FileWriteInteger(f,c.zones[i].distance);
      FileWriteInteger(f,c.zones[i].height);FileWriteInteger(f,c.zones[i].mopacity);FileWriteInteger(f,c.zones[i].group);
      FileWriteInteger(f,c.zones[i].open_line);FileWriteInteger(f,c.zones[i].stack);
      FileWriteInteger(f,(c.zones[i].enabled?1:0)|(c.zones[i].fill?2:0)|(c.zones[i].box?4:0)|(c.zones[i].extend?8:0)|(c.zones[i].alert?16:0)|(c.zones[i].midline?32:0));
     }
   FileWriteInteger(f,FPZ_END);
  }
bool FPZReadConfig(const int f,FPZoneConfig &c)
  {
   // Schema 1 (version 1.62) had no per-zone stack mode or separate midline switch.
   if(FileReadInteger(f)!=FPZ_MAGIC)return false;
   int schema=FileReadInteger(f);
   if(schema<1 || schema>FPZ_SCHEMA)return false;
   int flags=FileReadInteger(f);
   c.enabled=(flags&1)!=0;c.upcoming=(flags&2)!=0;c.fill=(flags&4)!=0;c.gradient=(flags&8)!=0;c.fade_old=(flags&16)!=0;
   c.lines_full=(flags&32)!=0;c.declutter=(flags&64)!=0;c.highlight=(flags&128)!=0;c.hover=(flags&256)!=0;
   c.alert_sound=(flags&512)!=0;c.alert_push=(flags&1024)!=0;
   c.cut=FPZCutLoad((flags>>11)&3);c.fib_lower=(flags>>13)&3;
   if(c.fib_lower>2)c.fib_lower=0;
   for(int g=0;g<FPZ_GROUPS;g++)
     {int v=FileReadInteger(f);c.group_on[g]=(v&1)!=0;c.group_tf[g]=v>>1;if(c.group_tf[g]<0 || c.group_tf[g]>20)return false;}
   c.days_back=FileReadInteger(f);c.dow_mask=FileReadInteger(f);c.broker_mode=FileReadInteger(f);c.broker_gmt=FileReadInteger(f);
   c.fill_mode=FileReadInteger(f);c.opacity=FileReadInteger(f);c.label_size=FileReadInteger(f);c.alert_lead=FileReadInteger(f);
   c.count=FileReadInteger(f);
   if(c.days_back<1 || c.days_back>60 || c.dow_mask<0 || c.dow_mask>127 || c.broker_mode<0 || c.broker_mode>4 || c.broker_gmt<-12 || c.broker_gmt>14
      || c.fill_mode<0 || c.fill_mode>2 || c.opacity<0 || c.opacity>100 || c.label_size<8 || c.label_size>24 || c.alert_lead<0 || c.alert_lead>120
      || c.count<0 || c.count>FPZ_MAX)return false;
   for(int i=0;i<c.count;i++)
     {
      if(!RText(f,c.zones[i].name,40))return false;
      c.zones[i].start=FileReadInteger(f);c.zones[i].end=FileReadInteger(f);c.zones[i].style=FileReadInteger(f);
      c.zones[i].width=FileReadInteger(f);c.zones[i].ink=(color)FileReadInteger(f);c.zones[i].label=FileReadInteger(f);
      c.zones[i].marker=FileReadInteger(f);c.zones[i].align=FileReadInteger(f);c.zones[i].distance=FileReadInteger(f);
      c.zones[i].height=FileReadInteger(f);c.zones[i].mopacity=FileReadInteger(f);c.zones[i].group=FileReadInteger(f);
      c.zones[i].open_line=FileReadInteger(f);
      c.zones[i].stack=schema>=2?FileReadInteger(f):0;
      int zf=FileReadInteger(f);
      c.zones[i].enabled=(zf&1)!=0;c.zones[i].fill=(zf&2)!=0;c.zones[i].box=(zf&4)!=0;c.zones[i].extend=(zf&8)!=0;c.zones[i].alert=(zf&16)!=0;
      // 1.62 drew the 50% line with the range box, and its edge markers ignored the distance.
      c.zones[i].midline=schema>=2?(zf&32)!=0:c.zones[i].box;
      if(schema<2 && (c.zones[i].marker==3 || c.zones[i].marker==4))c.zones[i].distance=0;
      if(c.zones[i].start<0 || c.zones[i].start>1439 || c.zones[i].end<0 || c.zones[i].end>1439 || c.zones[i].style<0 || c.zones[i].style>5
         || c.zones[i].width<1 || c.zones[i].width>5 || c.zones[i].label<0 || c.zones[i].label>2 || c.zones[i].marker<0 || c.zones[i].marker>4
         || c.zones[i].align<0 || c.zones[i].align>1 || c.zones[i].distance<0 || c.zones[i].distance>400 || c.zones[i].height<8 || c.zones[i].height>60
         || c.zones[i].stack<0 || c.zones[i].stack>1
         || c.zones[i].mopacity<0 || c.zones[i].mopacity>100 || c.zones[i].group<0 || c.zones[i].group>4 || c.zones[i].open_line<0 || c.zones[i].open_line>2)return false;
     }
   return FileReadInteger(f)==FPZ_END;
  }
bool FPZReadFile(const string filename,FPZoneConfig &c)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   FPZoneConfig candidate;
   bool good=FPZReadConfig(f,candidate) && FileTell(f)==FileSize(f);
   FileClose(f);
   if(good)c=candidate;
   return good;
  }
// Written to a temporary file, verified by reading it back, then swapped in (old copy kept as .bak).
bool FPZWriteFile(const string filename,FPZoneConfig &c)
  {
   string temporary=filename+".tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();FPZWriteConfig(f,c);FileFlush(f);int error=GetLastError();FileClose(f);
   FPZoneConfig check;
   if(error!=0 || !FPZReadFile(temporary,check) || check.count!=c.count)return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }

// ---- zone engine: occurrences, M1 data, live state and alerts
datetime ZoneNow(){datetime t=TimeTradeServer();if(t<=0)t=TimeCurrent();return t;}
// Broker clock model in use; "Auto" compares the server clock with UTC right now.
void ZoneResolveBroker()
  {
   int mode=g_zact.broker_mode,gmt=g_zact.broker_gmt;
   if(mode==0)
     {
      datetime server=TimeTradeServer(),utc=TimeGMT();
      mode=1;gmt=2;
      if(server>0 && utc>0)
        {
         long off=(long)MathRound(((double)server-(double)utc)/1800.0)*1800;
         long ny=FPUSDstUtc((long)utc)?-4*3600:-5*3600;
         if(off-ny!=7*3600){mode=2;gmt=(int)MathRound(off/3600.0);}
        }
     }
   if(mode!=g_zmode || gmt!=g_zgmt){g_zmode=mode;g_zgmt=gmt;g_zocc_dirty=true;}
  }
string ZoneBrokerText(const int mode)
  {
   if(mode==0)return "Auto-detect";
   if(mode==1)return "NY + 7 h (most brokers)";
   if(mode==2)return "GMT+N, no DST";
   if(mode==3)return "GMT+N, EU DST";
   return "GMT+N, US DST";
  }
// All occurrences of enabled zones over the last `days_back` trading days, plus today's
// upcoming ones. Market data is read lazily, only for occurrences that get drawn.
void ZonesBuild()
  {
   g_zocc_dirty=false;g_zocc_n=0;
   datetime now=ZoneNow();
   long td0=FPTradingDay(FPServerToNY((long)now,g_zmode,g_zgmt));
   g_zocc_daykey=(int)td0;
   if(!g_zact.enabled || g_zact.count==0)return;
   int days=Lim(g_zact.days_back,1,60);
   for(long td=td0-days+1;td<=td0;td++)
     {
      if((g_zact.dow_mask&(1<<FPDow(td)))==0)continue;
      for(int z=0;z<g_zact.count;z++)
        {
         if(!g_zact.zones[z].enabled || !g_zact.group_on[g_zact.zones[z].group])continue;
         long ny0=FPZoneNYStart(td,g_zact.zones[z].start),ny1=FPZoneNYEnd(ny0,g_zact.zones[z].start,g_zact.zones[z].end);
         datetime ts=(datetime)FPNYToServer(ny0,g_zmode,g_zgmt),te=(datetime)FPNYToServer(ny1,g_zmode,g_zgmt);
         bool future=ts>now;
         if(future && (td!=td0 || !g_zact.upcoming))continue;
         if(g_zocc_n>=ArraySize(g_zocc))ArrayResize(g_zocc,g_zocc_n+256);
         int i=g_zocc_n++;
         g_zocc[i].zone=z;g_zocc[i].day=(int)td;g_zocc[i].age=(int)(td0-td);g_zocc[i].state=0;
         g_zocc[i].ny=(datetime)ny0;g_zocc[i].ts=ts;g_zocc[i].te=te;
         g_zocc[i].future=future;g_zocc[i].live=!future && now<te;
         g_zocc[i].hi=0;g_zocc[i].lo=0;g_zocc[i].op=0;
         g_zocc[i].done_to=0;g_zocc[i].hi_taken=0;g_zocc[i].lo_taken=0;g_zocc[i].scan_to=0;
        }
     }
  }
// High, low and opening price from M1 bars, so a 20-minute macro is exact even on H1.
// Returns true when the stored values changed.
bool ZoneData(const int i,const datetime now)
  {
   if(g_zocc[i].future)
     {
      if(now<g_zocc[i].ts)return false;
      g_zocc[i].future=false;g_zocc[i].state=0;
     }
   g_zocc[i].live=now<g_zocc[i].te;
   bool line=g_zocc[i].te==g_zocc[i].ts;
   datetime stop=line?g_zocc[i].ts+3540:g_zocc[i].te-1;
   if(stop>now)stop=now;
   if(g_zocc[i].state==2)return false;
   if(g_zocc[i].state==1 && !g_zocc[i].live && g_zocc[i].done_to>=stop)return false;
   MqlRates r[];
   int n=CopyRates(_Symbol,PERIOD_M1,g_zocc[i].ts,stop,r);
   if(n<0){g_zocc[i].state=3;return false;}
   if(n==0){g_zocc[i].state=(g_zocc[i].live || now-stop<180)?3:2;return false;}
   double hi=r[0].high,lo=r[0].low;
   if(!line)for(int k=1;k<n;k++){if(r[k].high>hi)hi=r[k].high;if(r[k].low<lo)lo=r[k].low;}
   bool changed=g_zocc[i].state!=1 || hi!=g_zocc[i].hi || lo!=g_zocc[i].lo;
   g_zocc[i].hi=hi;g_zocc[i].lo=lo;g_zocc[i].op=r[0].open;g_zocc[i].state=1;g_zocc[i].done_to=stop;
   return changed;
  }
// "Extend until taken": the first M1 bar after the zone that trades through its high/low.
bool ZoneExtend(const int i,const datetime now)
  {
   if(g_zocc[i].state!=1 || g_zocc[i].live || g_zocc[i].ts==g_zocc[i].te)return false;
   if(g_zocc[i].hi_taken!=0 && g_zocc[i].lo_taken!=0)return false;
   datetime from=g_zocc[i].scan_to>g_zocc[i].te?g_zocc[i].scan_to:g_zocc[i].te;
   datetime limit=g_zocc[i].te+7*86400,stop=now<limit?now:limit;
   if(g_zocc[i].scan_to==0)g_zocc[i].scan_to=g_zocc[i].te;
   if(from>stop)return false;
   MqlRates r[];
   int n=CopyRates(_Symbol,PERIOD_M1,from,stop,r);
   if(n<=0)return false;
   bool changed=false;
   for(int k=0;k<n;k++)
     {
      if(g_zocc[i].hi_taken==0 && r[k].high>g_zocc[i].hi){g_zocc[i].hi_taken=r[k].time;changed=true;}
      if(g_zocc[i].lo_taken==0 && r[k].low<g_zocc[i].lo){g_zocc[i].lo_taken=r[k].time;changed=true;}
      if(g_zocc[i].hi_taken!=0 && g_zocc[i].lo_taken!=0)break;
     }
   g_zocc[i].scan_to=r[n-1].time+60;
   return changed;
  }
uint FPZoneHash(FPZone &z)
  {
   uint h=2166136261;string s=z.name+"|"+IntegerToString(z.start)+"|"+IntegerToString(z.end);
   for(int i=0;i<StringLen(s);i++){h^=(uint)StringGetCharacter(s,i);h*=16777619;}
   return h;
  }
// One alert per zone and trading day across every chart of this workspace: the first
// chart to flip the terminal-wide flag sends it.
bool ZoneAlertClaim(const int z,const long td)
  {
   string key="FPZ."+WorkspaceTag()+"."+IntegerToString((long)FPZoneHash(g_zact.zones[z]))+"."+IntegerToString(td);
   GlobalVariableTemp(key);
   return GlobalVariableSetOnCondition(key,1.0,0.0);
  }
void ZoneFireAlert(const string name,const int start,const bool test)
  {
   string when=test?"test alert":(g_zact.alert_lead>0?"starts in "+IntegerToString(g_zact.alert_lead)+" min":"starts now");
   string msg="Fibonacci Pro: "+name+" "+when+" ("+FPHHMM(start)+" New York)";
   if(g_zact.alert_sound)PlaySound("alert.wav");
   if(g_zact.alert_push && !SendNotification(msg))
      Print("Fibonacci Pro: push notification not sent. Enable it in Tools > Options > Notifications with your MetaQuotes ID.");
   Print(msg);Status(msg);
  }
void ZoneAlerts(const datetime now)
  {
   if(!g_zact.enabled || (!g_zact.alert_sound && !g_zact.alert_push))return;
   long now_ny=FPServerToNY((long)now,g_zmode,g_zgmt),td0=FPTradingDay(now_ny);
   for(int z=0;z<g_zact.count;z++)
     {
      if(!g_zact.zones[z].enabled || !g_zact.zones[z].alert || !g_zact.group_on[g_zact.zones[z].group])continue;
      for(long td=td0;td<=td0+1;td++)
        {
         if((g_zact.dow_mask&(1<<FPDow(td)))==0)continue;
         long at=FPZoneNYStart(td,g_zact.zones[z].start)-(long)g_zact.alert_lead*60;
         if(now_ny<at || now_ny>=at+90)continue;
         if(ZoneAlertClaim(z,td))ZoneFireAlert(g_zact.zones[z].name,g_zact.zones[z].start,false);
        }
     }
  }
// The Zones button takes the colour of the live zone; its tooltip is a small clock.
void UpdateZonesButton()
  {
   if(g_hidden || !g_owner)return;
   color bg=g_zeditor?clrLightSteelBlue:(g_zlive_on?g_zlive_ink:clrWhite);
   Button("T.Zones","Zones",g_toolbar_x+U(FP_TOOLBAR_WIDTH-92),g_toolbar_y+U(1),60,18,bg);
   Tooltip("T.Zones",g_zbutton_tip);
  }
void ZoneLiveState(const datetime now)
  {
   long now_ny=FPServerToNY((long)now,g_zmode,g_zgmt),td0=FPTradingDay(now_ny);
   string live="",next="";long best=-1,left=0,next_in=-1;color ink=clrWhite;
   if(g_zact.enabled)
      for(int z=0;z<g_zact.count;z++)
        {
         if(!g_zact.zones[z].enabled || !g_zact.group_on[g_zact.zones[z].group])continue;
         for(long td=td0;td<=td0+1;td++)
           {
            if((g_zact.dow_mask&(1<<FPDow(td)))==0)continue;
            long s=FPZoneNYStart(td,g_zact.zones[z].start),e=FPZoneNYEnd(s,g_zact.zones[z].start,g_zact.zones[z].end);
            // The most specific (shortest) live zone wins the button colour.
            if(e>s && now_ny>=s && now_ny<e && (best<0 || e-s<best)){best=e-s;live=g_zact.zones[z].name;left=e-now_ny;ink=g_zact.zones[z].ink;}
            if(s>now_ny && (next_in<0 || s-now_ny<next_in)){next_in=s-now_ny;next=g_zact.zones[z].name;}
           }
        }
   string tip="New York "+FPHHMM((int)(FPFloorDiv(now_ny,60)%1440));
   if(!g_zact.enabled)tip+=" | zones hidden ("+InpZonesHotkey+" to show)";
   else
     {
      tip+=StringLen(live)>0?" | Live: "+live+", "+FPDuration(left)+" left":" | No zone live";
      if(StringLen(next)>0)tip+=" | Next: "+next+" in "+FPDuration(next_in);
     }
   tip+=" | Click to set up sessions, killzones & macros";
   bool on=StringLen(live)>0;
   if(tip==g_zbutton_tip && on==g_zlive_on && ink==g_zlive_ink)return;
   g_zbutton_tip=tip;g_zlive_on=on;g_zlive_ink=ink;
   UpdateZonesButton();g_need_redraw=true;
  }
bool SaveZones()
  {
   if(g_zstore=="" || !g_owner)return false;
   if(!FPZWriteFile(g_zstore,g_zcfg)){Print("Fibonacci Pro: could not save zone settings, error ",GetLastError());return false;}
   g_zstore_mtime=(datetime)FileGetInteger(g_zstore,FILE_MODIFY_DATE);
   return true;
  }
void LoadZones()
  {
   if(!FPZReadFile(g_zstore,g_zcfg) && !FPZReadFile(g_zstore+".bak",g_zcfg))FPZoneDefaults(g_zcfg,false);
   g_zstore_mtime=FileIsExist(g_zstore)?(datetime)FileGetInteger(g_zstore,FILE_MODIFY_DATE):0;
   g_zact=g_zcfg;g_zocc_dirty=true;g_zone_resolve=0;
  }
// Settings are shared by every chart of the workspace: pick up another chart's changes.
void ZonePollShared()
  {
   if(g_zeditor || g_zstore=="" || !FileIsExist(g_zstore))return;
   datetime m=(datetime)FileGetInteger(g_zstore,FILE_MODIFY_DATE);
   if(m<=0 || m==g_zstore_mtime)return;
   FPZoneConfig loaded;
   if(!FPZReadFile(g_zstore,loaded))return;
   g_zcfg=loaded;g_zact=g_zcfg;g_zstore_mtime=m;g_zocc_dirty=true;g_zone_resolve=0;g_dirty=true;
  }
// Once a second: day roll-over, live zones, liquidity sweeps, button state, alerts.
void ZoneTick(const ulong tick)
  {
   if(tick-g_zone_tick<1000)return;
   g_zone_tick=tick;
   if(g_zone_resolve==0 || tick-g_zone_resolve>=60000){g_zone_resolve=tick;ZoneResolveBroker();}
   datetime now=ZoneNow();
   long td0=FPTradingDay(FPServerToNY((long)now,g_zmode,g_zgmt));
   if(g_zocc_dirty || td0!=g_zocc_daykey){ZonesBuild();g_dirty=true;}
   bool retry=tick-g_zone_retry>=30000;
   if(retry)g_zone_retry=tick;
   for(int i=0;i<g_zocc_n;i++)
     {
      if(retry && (g_zocc[i].state==2 || g_zocc[i].state==3))g_zocc[i].state=0;
      bool refresh=g_zocc[i].live || (g_zocc[i].future && now>=g_zocc[i].ts) || (g_zocc[i].state==1 && g_zocc[i].done_to<g_zocc[i].te-1 && now>=g_zocc[i].te);
      if(refresh && ZoneData(i,now))g_dirty=true;
      int z=g_zocc[i].zone;
      if(z<g_zact.count && g_zact.zones[z].extend && g_zocc[i].scan_to>0 && ZoneExtend(i,now))g_dirty=true;
     }
   ZoneLiveState(now);
   ZoneAlerts(now);
   if(tick-g_zone_poll>=2000){g_zone_poll=tick;ZonePollShared();}
  }

// ---- zone drawing: fills on the background canvas, strips/lines/text on the front one
int FPSortUnique(int &v[],const int n)
  {
   for(int i=1;i<n;i++){int x=v[i],j=i;while(j>0 && v[j-1]>x){v[j]=v[j-1];j--;}v[j]=x;}
   int m=0;
   for(int i=0;i<n;i++)if(m==0 || v[i]!=v[m-1])v[m++]=v[i];
   return m;
  }
void FPLayerSet(FPLayer &l,const int x0,const int x1,const int y0,const int y1,const color ink,const color ink2,const double a0,const double a1,const int kind)
  {l.x0=x0;l.x1=x1;l.y0=y0;l.y1=y1;l.ink=ink;l.ink2=ink2;l.a0=a0;l.a1=a1;l.kind=kind;}
// Colour of one pixel row y of the cell [ya,yb): every covering layer, "over" in list
// order. Fib layers (kind 1) keep `keep` of their opacity (less inside zone shading).
uint FPComposeRow(FPLayer &layers[],int &cover[],const int nc,const int ya,const int yb,const double y,const double keep)
  {
   double r=0,g=0,b=0,a=0;
   for(int q=0;q<nc;q++)
     {
      int i=cover[q];
      if(layers[i].y0>ya || layers[i].y1<yb-1)continue;
      double t=layers[i].y1>layers[i].y0?(y-layers[i].y0)/(double)(layers[i].y1-layers[i].y0):0;
      t=MathMax(0.0,MathMin(1.0,t));
      double al=layers[i].a0+(layers[i].a1-layers[i].a0)*t;
      if(layers[i].kind==1)al*=keep;
      if(al<=0)continue;
      int c=(int)(layers[i].ink2==layers[i].ink?layers[i].ink:FPBlend(layers[i].ink,layers[i].ink2,t));
      r=(c&255)*al+r*(1-al);g=((c>>8)&255)*al+g*(1-al);b=((c>>16)&255)*al+b*(1-al);a=al+a*(1-al);
     }
   if(a<0.004)return 0;
   return ((uint)Lim((int)MathRound(a*255),0,255)<<24)|((uint)Lim((int)MathRound(r/a),0,255)<<16)
          |((uint)Lim((int)MathRound(g/a),0,255)<<8)|(uint)Lim((int)MathRound(b/a),0,255);
  }
// Exact "over" compositing of translucent rectangles (in list order). The canvas only
// stores pixels, so overlapping layers are split into cells whose colour already includes
// everything underneath: nothing wipes out what lies below it. Inside zone shading
// (kind 0), Fib fills (kind 1) lose `cut` of their opacity, so zones stay easy to see.
int FPComposeSegments(FPLayer &layers[],const int n,const int w,const int h,FPSeg &segs[],const double cut=0.0)
  {
   int count=0;
   if(n<=0 || w<=0 || h<=0)return 0;
   int xs[];ArrayResize(xs,2*n+2);int nx=0;
   for(int i=0;i<n;i++)
     {
      if(layers[i].x0>layers[i].x1 || layers[i].y0>layers[i].y1 || layers[i].x1<0 || layers[i].x0>=w || layers[i].y1<0 || layers[i].y0>=h)continue;
      xs[nx++]=Lim(layers[i].x0,0,w);xs[nx++]=Lim(layers[i].x1+1,0,w);
     }
   nx=FPSortUnique(xs,nx);
   double keep=1.0-MathMax(0.0,MathMin(1.0,cut));
   int ys[];int cover[];ArrayResize(cover,n);
   for(int sx=0;sx+1<nx;sx++)
     {
      int xa=xs[sx],xb=xs[sx+1],ny=0,nc=0;bool grad=false;
      ArrayResize(ys,2*n+2);
      for(int i=0;i<n;i++)
        {
         if(layers[i].x0>layers[i].x1 || layers[i].y0>layers[i].y1 || layers[i].x0>xa || layers[i].x1<xb-1 || layers[i].y1<0 || layers[i].y0>=h)continue;
         cover[nc++]=i;
         int a=Lim(layers[i].y0,0,h),b=Lim(layers[i].y1+1,0,h);
         ys[ny++]=a;ys[ny++]=b;
         if(layers[i].a0!=layers[i].a1)grad=true;
        }
      if(ny==0)continue;
      // Opacity gradients (zone shading) are sampled in bands that each change the
      // opacity by about 1/255 or less, so the steps can't be seen.
      if(grad)
         for(int q=0;q<nc;q++)
           {
            int i=cover[q];
            if(layers[i].a0==layers[i].a1)continue;
            int a=Lim(layers[i].y0,0,h),b=Lim(layers[i].y1+1,0,h);
            int step=(int)MathMax(6,(layers[i].y1-layers[i].y0+1)/(MathAbs(layers[i].a1-layers[i].a0)*255+1));
            if(ny+(b-a)/step+2>ArraySize(ys))ArrayResize(ys,ny+(b-a)/step+2);
            for(int yy=a+step;yy<b;yy+=step)ys[ny++]=yy;
           }
      ny=FPSortUnique(ys,ny);
      for(int sy=0;sy+1<ny;sy++)
        {
         int ya=ys[sy],yb=ys[sy+1];
         bool zone=false,cgrad=false;
         for(int q=0;q<nc;q++)
           {
            int i=cover[q];
            if(layers[i].y0>ya || layers[i].y1<yb-1)continue;
            if(layers[i].kind==0)zone=true;
            if(layers[i].ink2!=layers[i].ink)cgrad=true;
           }
         double k=zone?keep:1.0;
         uint top=0,bottom=0;
         // A colour gradient is linear inside a cell: its top and bottom rows define it.
         if(cgrad && yb-1>ya){top=FPComposeRow(layers,cover,nc,ya,yb,ya,k);bottom=FPComposeRow(layers,cover,nc,ya,yb,yb-1,k);}
         else {top=FPComposeRow(layers,cover,nc,ya,yb,(ya+yb-1)*0.5,k);bottom=top;}
         if(top==0)top=bottom;
         if(bottom==0)bottom=top;
         if(top==0)continue;
         if(count>=ArraySize(segs))ArrayResize(segs,count+64);
         segs[count].x0=xa;segs[count].x1=xb-1;segs[count].y0=ya;segs[count].y1=yb-1;segs[count].argb=top;segs[count].argb1=bottom;
         count++;
        }
     }
   return count;
  }
uint FPLerpARGB(const uint c0,const uint c1,const double t)
  {
   uint result=0;
   for(int shift=0;shift<=24;shift+=8)
     {
      int v0=(int)((c0>>shift)&255),v1=(int)((c1>>shift)&255);
      result|=(uint)Lim((int)MathRound(v0+(v1-v0)*t),0,255)<<shift;
     }
   return result;
  }
// Largest change between two colours as it shows on screen: the opacity change, or a
// colour change scaled by the opacity it is seen through.
int FPVisibleDelta(const uint c0,const uint c1)
  {
   int a0=(int)(c0>>24),a1=(int)(c1>>24),am=(int)MathMax(a0,a1),d=(int)MathAbs(a0-a1);
   for(int shift=0;shift<=16;shift+=8)
     {
      int v=(int)MathAbs((int)((c0>>shift)&255)-(int)((c1>>shift)&255))*am/255;
      if(v>d)d=v;
     }
   return d;
  }
void DrawLayers(CCanvas &cv,FPLayer &layers[],const int n,const int w,const int h,const double cut=0.0)
  {
   FPSeg segs[];
   int count=FPComposeSegments(layers,n,w,h,segs,cut);
   for(int i=0;i<count;i++)
     {
      int y0=segs[i].y0,rows=segs[i].y1-y0+1;
      if(segs[i].argb==segs[i].argb1 || rows<=1)
        {cv.FillRectangle(segs[i].x0,y0,segs[i].x1,segs[i].y1,segs[i].argb);continue;}
      // A colour gradient, in bands that each change by at most one visible step: the
      // same picture as row by row, with far fewer calls at low opacity.
      int bands=(int)MathMin(rows,FPVisibleDelta(segs[i].argb,segs[i].argb1)+1);
      for(int b=0;b<bands;b++)
        {
         int ya=y0+(int)((long)rows*b/bands),yb=y0+(int)((long)rows*(b+1)/bands)-1;
         cv.FillRectangle(segs[i].x0,ya,segs[i].x1,yb,FPLerpARGB(segs[i].argb,segs[i].argb1,((ya+yb)*0.5-y0)/(rows-1)));
        }
     }
  }
// ---- background shading: Fib fills and zone fills blended in one pass
// On charts below a Fib's own timeframe its shading can be faint (a third) or off.
double FibShadeFactor(FPSetup &s)
  {
   int own=TFIndex(s.source_tf);
   if(g_zact.fib_lower==0 || own<0 || g_tf<0 || g_tf>=own)return 1.0;
   return g_zact.fib_lower==1?1.0/3.0:0.0;
  }
bool FibShadeLayer(FPSetup &s,const int slot,FPLayer &l)
  {
   int x0=0,y0=0,x1=0,y1=0,top=0,bottom=0;
   if(!FillRect(s,slot,x0,y0,x1,y1,top,bottom))return false;
   double a=s.opacity/100.0*FibShadeFactor(s);
   if(a<=0)return false;
   FPLayerSet(l,x0,x1,top,bottom,s.fill_top,s.gradient?s.fill_bottom:s.fill_top,a,a,1);
   return true;
  }
// Drawing order: higher drawing timeframes first (underneath); within a timeframe the
// selected Fib last, otherwise in list order.
bool ShadeBefore(const int a,const int b)
  {
   if(g_shade_tf[a]!=g_shade_tf[b])return g_shade_tf[a]>g_shade_tf[b];
   bool sa=g_shade_slot[a]==g_selected,sb=g_shade_slot[b]==g_selected;
   if(sa!=sb)return sb;
   return g_shade_slot[a]<g_shade_slot[b];
  }
// All background shading in one blended pass: Fib fills underneath, zone fills on top.
void ShadeDraw(const bool sel)
  {
   int cap=g_count+g_zfill_n+1;
   if(ArraySize(g_shade)<cap)ArrayResize(g_shade,cap);
   if(ArraySize(g_shade_fib)<g_count+1)
     {ArrayResize(g_shade_fib,g_count+1);ArrayResize(g_shade_tf,g_count+1);ArrayResize(g_shade_slot,g_count+1);ArrayResize(g_shade_ord,g_count+1);}
   int nf=0;
   for(int i=0;i<g_count;i++)
     {
      bool editing=sel && g_editor && i==g_selected;
      if(editing){if(!FibShadeLayer(g_edit,i,g_shade_fib[nf]))continue;g_shade_tf[nf]=TFIndex(g_edit.source_tf);}
      else {if(!FibShadeLayer(g_sets[i],i,g_shade_fib[nf]))continue;g_shade_tf[nf]=TFIndex(g_sets[i].source_tf);}
      g_shade_slot[nf]=i;g_shade_ord[nf]=nf;nf++;
     }
   for(int u=1;u<nf;u++){int v=g_shade_ord[u],j=u;while(j>0 && ShadeBefore(v,g_shade_ord[j-1])){g_shade_ord[j]=g_shade_ord[j-1];j--;}g_shade_ord[j]=v;}
   int n=0;
   for(int k=0;k<nf;k++)g_shade[n++]=g_shade_fib[g_shade_ord[k]];
   for(int k=0;k<g_zfill_n;k++)g_shade[n++]=g_zfill[k];
   double cut=g_zact.cut==2?1.0:(g_zact.cut==1?0.5:0.0);
   DrawLayers(g_fill_canvas,g_shade,n,g_width,g_height,cut);
  }
void VLine(const int x,const int y0,const int y1,const color ink,const int width,const int style,const uchar alpha=255)
  {
   if(style>=5 || x+width<0 || x-width>=g_width || y1<0 || y0>=g_height)return;
   int l=Lim(x-(width-1)/2,0,g_width-1),r=Lim(x-(width-1)/2+width-1,0,g_width-1),t=Lim(y0,0,g_height-1),b=Lim(y1,0,g_height-1);
   if(t>b || l>r)return;
   uint argb=ColorToARGB(ink,alpha);
   if(style==STYLE_SOLID){g_line_canvas.FillRectangle(l,t,r,b,argb);return;}
   int cycle=0,parts=style==3?4:(style==4?6:2);
   for(int k=0;k<parts;k++)cycle+=FPPatternLength(style,k,width);
   int phase=(int)(((long)t-(long)y0)%cycle),part=0;
   while(phase>=FPPatternLength(style,part,width)){phase-=FPPatternLength(style,part,width);part++;}
   int pos=t;
   while(pos<=b)
     {int length=FPPatternLength(style,part,width)-phase;
      if(part%2==0)g_line_canvas.FillRectangle(l,pos,r,(int)MathMin(b,pos+length-1),argb);
      pos+=length;part=(part+1)%parts;phase=0;}
  }
int ZoneHalfBar(){return (1<<(int)Lim((int)g_view_scale,0,5))/2;}
// Pixel x of a server time at the left edge of its bar, so zone edges sit between bars.
bool ZoneX(const datetime t,int &x){int y=0;if(!XY(t,g_view_max,x,y))return false;x-=ZoneHalfBar();return true;}
datetime ZoneDayEnd(const int i){return (datetime)FPNYToServer((long)g_zocc[i].day*86400+17*3600,g_zmode,g_zgmt);}
// Right-most time an occurrence draws to (liquidity lines, opening-price line).
datetime ZoneReach(const int i,const datetime now)
  {
   int z=g_zocc[i].zone;datetime reach=g_zocc[i].te;
   if(g_zact.zones[z].open_line==2){datetime e=ZoneDayEnd(i);if(e>reach)reach=e;}
   if(g_zact.zones[z].extend)
     {
      datetime h=g_zocc[i].hi_taken>0?g_zocc[i].hi_taken:now,l=g_zocc[i].lo_taken>0?g_zocc[i].lo_taken:now;
      if(h>reach)reach=h;
      if(l>reach)reach=l;
     }
   return reach;
  }
double ZoneAlpha(const int i,const double base)
  {
   double a=base;
   if(g_zact.fade_old && g_zact.days_back>1)a*=MathMax(0.35,1.0-0.65*g_zocc[i].age/(double)(g_zact.days_back-1));
   if(g_zact.highlight && g_zocc[i].live)a=MathMin(1.0,a*1.7);
   return a;
  }
void ZoneAddFill(const int x0,const int x1,const int y0,const int y1,const color ink,const double a,const bool gradient)
  {
   if(g_zfill_n>=ArraySize(g_zfill))ArrayResize(g_zfill,g_zfill_n+32);
   FPLayerSet(g_zfill[g_zfill_n],x0,x1,y0,y1,ink,ink,a,gradient?a*0.15:a,0);
   g_zfill_n++;
  }
// Screen data of the occurrences drawn this frame (reused by hover) and the fill layers.
void ZonesPrepare()
  {
   g_zvis_n=0;g_zfill_n=0;g_zfill_sig=0;
   if(g_zocc_dirty){ZoneResolveBroker();ZonesBuild();}
   if(!g_zact.enabled || g_zocc_n==0)return;
   datetime now=ZoneNow();
   int budget=40; // M1 reads per frame; the rest continue on the next frame
   for(int i=g_zocc_n-1;i>=0;i--) // newest first, so today's zones appear on the first frame
     {
      int z=g_zocc[i].zone;
      if(z>=g_zact.count || g_tf>g_zact.group_tf[g_zact.zones[z].group])continue;
      if(g_cull_ok && (ZoneReach(i,now)<g_vt0 || g_zocc[i].ts>g_vt1))continue;
      if(g_zocc[i].state==0 || (g_zocc[i].future && now>=g_zocc[i].ts))
        {if(budget>0){budget--;ZoneData(i,now);}else g_dirty=true;}
      if(g_zocc[i].state==2)continue;                                       // holiday: no bars at all
      if(g_zocc[i].state!=1 && !g_zocc[i].future && !g_zocc[i].live)continue; // history still loading
      if(g_zact.zones[z].extend && g_zocc[i].scan_to==0 && g_zocc[i].state==1 && !g_zocc[i].live)
        {if(budget>0){budget--;ZoneExtend(i,now);}else g_dirty=true;}
      int x0=0,x1=0;
      if(!ZoneX(g_zocc[i].ts,x0))continue;
      if(g_zocc[i].te!=g_zocc[i].ts){if(!ZoneX(g_zocc[i].te,x1))continue;if(x1<x0)x1=x0;}
      else x1=x0;
      if(g_zvis_n>=ArraySize(g_zvis))ArrayResize(g_zvis,g_zvis_n+64);
      int v=g_zvis_n++;
      g_zvis[v].occ=i;g_zvis[v].x0=x0;g_zvis[v].x1=x1;g_zvis[v].yh=FP_OFF;g_zvis[v].yl=FP_OFF;g_zvis[v].yo=FP_OFF;
      if(g_zocc[i].state==1)
        {
         int ignore=0,y=0;
         if(XY(g_zocc[i].ts,g_zocc[i].hi,ignore,y))g_zvis[v].yh=y;
         if(XY(g_zocc[i].ts,g_zocc[i].lo,ignore,y))g_zvis[v].yl=y;
         if(XY(g_zocc[i].ts,g_zocc[i].op,ignore,y))g_zvis[v].yo=y;
        }
      // Ends of the extended high/low (taken time, else the chart's right edge) and of the
      // opening-price line; shared by drawing and hover.
      g_zvis[v].xh=g_width-1;g_zvis[v].xl=g_width-1;g_zvis[v].xe=x1;
      if(g_zocc[i].hi_taken>0)ZoneX(g_zocc[i].hi_taken,g_zvis[v].xh);
      if(g_zocc[i].lo_taken>0)ZoneX(g_zocc[i].lo_taken,g_zvis[v].xl);
      if(g_zact.zones[z].open_line==2)ZoneX(ZoneDayEnd(i),g_zvis[v].xe);
      if(g_zvis[v].xe<=x0)g_zvis[v].xe=x0+1;
     }
   // Fill layers: longer (outer) zones first, so nested zones shade on top of them.
   int order[];ArrayResize(order,g_zvis_n);int n=0;
   for(int v=0;v<g_zvis_n;v++)
     {int i=g_zvis[v].occ;if(g_zact.fill && g_zact.zones[g_zocc[i].zone].fill && g_zocc[i].te>g_zocc[i].ts)order[n++]=v;}
   for(int a=1;a<n;a++)
     {
      int v=order[a],j=a;long d=(long)(g_zocc[g_zvis[v].occ].te-g_zocc[g_zvis[v].occ].ts);
      while(j>0 && (long)(g_zocc[g_zvis[order[j-1]].occ].te-g_zocc[g_zvis[order[j-1]].occ].ts)<d){order[j]=order[j-1];j--;}
      order[j]=v;
     }
   for(int k=0;k<n;k++)
     {
      int v=order[k],i=g_zvis[v].occ,z=g_zocc[i].zone;
      double a=ZoneAlpha(i,g_zact.opacity/100.0);
      bool box=g_zvis[v].yh!=FP_OFF && g_zvis[v].yl!=FP_OFF;
      if(g_zact.fill_mode!=1 || !box)ZoneAddFill(g_zvis[v].x0,g_zvis[v].x1-1,0,g_height-1,g_zact.zones[z].ink,a,g_zact.gradient);
      if(g_zact.fill_mode!=0 && box)ZoneAddFill(g_zvis[v].x0,g_zvis[v].x1-1,g_zvis[v].yh,g_zvis[v].yl,g_zact.zones[z].ink,g_zact.fill_mode==2?MathMin(1.0,a*2):a,g_zact.gradient);
     }
   ulong sig=FPMix((ulong)1469598103934665603,g_zfill_n);
   for(int k=0;k<g_zfill_n;k++)
     {
      sig=FPMix(sig,g_zfill[k].x0);sig=FPMix(sig,g_zfill[k].x1);sig=FPMix(sig,g_zfill[k].y0);sig=FPMix(sig,g_zfill[k].y1);
      sig=FPMix(sig,(long)g_zfill[k].ink);sig=FPMix(sig,(long)MathRound(g_zfill[k].a0*1000));sig=FPMix(sig,(long)MathRound(g_zfill[k].a1*1000));
     }
   g_zfill_sig=sig;
  }
string ZoneLabelText(const int z)
  {
   if(g_zact.zones[z].label==0)return "";
   string t=g_zact.zones[z].name;
   if(g_zact.zones[z].label==2)t+=" "+FPHHMM(g_zact.zones[z].start)+(g_zact.zones[z].end!=g_zact.zones[z].start?"-"+FPHHMM(g_zact.zones[z].end):"");
   return t;
  }
// Placement order: fixed strips first (they never move), then longer zones, then earlier.
bool ZoneMarkFirst(const int a,const int b)
  {
   if(g_zmark[a].fixed!=g_zmark[b].fixed)return g_zmark[a].fixed;
   long da=g_zmark[a].te-g_zmark[a].ts,db=g_zmark[b].te-g_zmark[b].ts;
   if(da!=db)return da>db;
   if(g_zmark[a].x0!=g_zmark[b].x0)return g_zmark[a].x0<g_zmark[b].x0;
   return a<b;
  }
// Every zone keeps its own strip. A fixed strip sits exactly `distance` pixels from its
// zone's low/high or from the chart edge; an automatic one starts there and steps away
// (from price, or from the edge) past any strip it would overlap.
void ZonesLayoutAnchor(const int a)
  {
   int idx[];ArrayResize(idx,g_zmark_n);int m=0;
   for(int k=0;k<g_zmark_n;k++)if(g_zmark[k].anchor==a)idx[m++]=k;
   if(m==0)return;
   for(int u=1;u<m;u++){int v=idx[u],j=u;while(j>0 && ZoneMarkFirst(v,idx[j-1])){idx[j]=idx[j-1];j--;}idx[j]=v;}
   bool down=(a==1 || a==4);   // below the low and from the top edge: strips step downwards
   for(int u=0;u<m;u++)
     {
      int c=idx[u],h=g_zmark[c].y1-g_zmark[c].y0,y0=g_zmark[c].start;
      if(!g_zmark[c].fixed)
        {
         bool moved=true;int guard=0;
         while(moved && guard++<4*m+8)
           {
            moved=false;
            for(int q=0;q<u;q++)
              {
               int p=idx[q];
               if(g_zmark[c].x0>g_zmark[p].x1 || g_zmark[p].x0>g_zmark[c].x1)continue;   // touching strips share a row
               if(y0<g_zmark[p].y1+2 && g_zmark[p].y0<y0+h+2)
                 {y0=down?g_zmark[p].y1+2:g_zmark[p].y0-2-h;moved=true;}
              }
           }
        }
      g_zmark[c].y0=y0;g_zmark[c].y1=y0+h;
     }
  }
void ZonesLayout()
  {
   g_zmark_n=0;
   int th=g_line_canvas.TextHeight("Ag");
   for(int v=0;v<g_zvis_n;v++)
     {
      int i=g_zvis[v].occ,z=g_zocc[i].zone;
      if(g_zact.zones[z].marker==0 && g_zact.zones[z].label==0)continue;
      string text=ZoneLabelText(z);
      int tw=StringLen(text)>0?g_line_canvas.TextWidth(text):0;
      int anchor=g_zact.zones[z].marker!=0?g_zact.zones[z].marker:4;
      bool range=g_zvis[v].yh!=FP_OFF && g_zvis[v].yl!=FP_OFF;
      if((anchor==1 || anchor==2) && !range)anchor=anchor==1?3:4; // no high/low yet: use the chart edge
      if(g_zmark_n>=ArraySize(g_zmark))ArrayResize(g_zmark,g_zmark_n+32);
      int k=g_zmark_n++,pad=4;
      bool shade=g_zact.zones[z].marker!=0;
      int h=shade?(int)MathMax(g_zact.zones[z].height,th+2):th+2,d=g_zact.zones[z].distance;
      g_zmark[k].vis=v;g_zmark[k].anchor=anchor;g_zmark[k].text=text;g_zmark[k].tw=tw;g_zmark[k].shade=shade;
      g_zmark[k].ts=(long)g_zocc[i].ts;g_zmark[k].te=(long)g_zocc[i].te;g_zmark[k].fixed=g_zact.zones[z].stack==1;
      g_zmark[k].alpha=shade?ZoneAlpha(i,g_zact.zones[z].mopacity/100.0):0;
      if(g_zocc[i].te==g_zocc[i].ts){int w=tw+2*pad;g_zmark[k].x0=g_zvis[v].x0-w/2;g_zmark[k].x1=g_zmark[k].x0+w;}
      else {g_zmark[k].x0=g_zvis[v].x0;g_zmark[k].x1=g_zvis[v].x1-1;}
      int start=anchor==1?g_zvis[v].yl+d:(anchor==2?g_zvis[v].yh-d-h:(anchor==3?g_height-d-h:d));
      g_zmark[k].start=start;g_zmark[k].y0=start;g_zmark[k].y1=start+h;
     }
   for(int a=1;a<=4;a++)ZonesLayoutAnchor(a);
  }
color ZoneTextInk(const color ink,const double alpha,const bool shade)
  {
   if(!shade)return ink;
   if(alpha<0.35)return g_chart_fg;
   color mix=FPBlend(g_chart_bg,ink,alpha);
   double lum=.299*((int)mix&255)+.587*(((int)mix>>8)&255)+.114*(((int)mix>>16)&255);
   return lum<140?clrWhite:clrBlack;
  }
void ZonesDraw()
  {
   g_zmark_n=0;
   if(g_zvis_n==0)return;
   g_line_canvas.FontSet("Segoe UI",g_zact.label_size);
   ZonesLayout();
   // 1. Strip shading (composited, so a fixed strip placed over another still blends).
   FPLayer strips[];ArrayResize(strips,g_zmark_n);int ns=0;
   for(int k=0;k<g_zmark_n;k++)
     {
      if(!g_zmark[k].shade || g_zmark[k].alpha<=0 || g_zmark[k].x1<g_zmark[k].x0)continue;
      int z=g_zocc[g_zvis[g_zmark[k].vis].occ].zone;
      FPLayerSet(strips[ns],g_zmark[k].x0,g_zmark[k].x1,g_zmark[k].y0,g_zmark[k].y1-1,g_zact.zones[z].ink,g_zact.zones[z].ink,g_zmark[k].alpha,g_zmark[k].alpha,0);ns++;
     }
   DrawLayers(g_line_canvas,strips,ns,g_width,g_height);
   // 2. Boundary lines, range boxes, midlines, liquidity lines and opening prices.
   for(int v=0;v<g_zvis_n;v++)
     {
      int i=g_zvis[v].occ,z=g_zocc[i].zone,x0=g_zvis[v].x0,x1=g_zvis[v].x1;
      color ink=g_zact.zones[z].ink;
      uchar la=(uchar)MathRound(255*MathMin(1.0,ZoneAlpha(i,1.0)));
      bool range=g_zvis[v].yh!=FP_OFF && g_zvis[v].yl!=FP_OFF;
      if(g_zact.zones[z].style<5)
        {
         int ya=0,yb=g_height-1;
         if(!g_zact.lines_full && range){ya=g_zvis[v].yh;yb=g_zvis[v].yl;}
         VLine(x0,ya,yb,ink,g_zact.zones[z].width,g_zact.zones[z].style,la);
         if(x1!=x0)VLine(x1,ya,yb,ink,g_zact.zones[z].width,g_zact.zones[z].style,la);
        }
      if(g_zact.zones[z].box && range && x1>x0)
        {
         HLine(x0,x1,g_zvis[v].yh,ink,1,STYLE_SOLID,la);HLine(x0,x1,g_zvis[v].yl,ink,1,STYLE_SOLID,la);
         VLine(x0,g_zvis[v].yh,g_zvis[v].yl,ink,1,STYLE_SOLID,la);VLine(x1,g_zvis[v].yh,g_zvis[v].yl,ink,1,STYLE_SOLID,la);
        }
      if(g_zact.zones[z].midline && range && x1>x0)HLine(x0,x1,(g_zvis[v].yh+g_zvis[v].yl)/2,ink,1,STYLE_DASH,la);
      if(g_zact.zones[z].extend && range && !g_zocc[i].live && g_zocc[i].te>g_zocc[i].ts)
        {HLine(x1,g_zvis[v].xh,g_zvis[v].yh,ink,1,STYLE_DOT,la);HLine(x1,g_zvis[v].xl,g_zvis[v].yl,ink,1,STYLE_DOT,la);}
      if(g_zact.zones[z].open_line>0 && g_zvis[v].yo!=FP_OFF)
        {
         int xe=g_zvis[v].xe;
         HLine(x0,xe,g_zvis[v].yo,ink,1,STYLE_DASH,la);
         if(g_zact.zones[z].label>0)
           {
            string t=g_zact.zones[z].name+" "+DoubleToString(g_zocc[i].op,_Digits);
            int tw=g_line_canvas.TextWidth(t),th=g_line_canvas.TextHeight(t);
            g_line_canvas.TextOut(Lim(xe-tw-4,2,(int)MathMax(2,g_width-tw-2)),g_zvis[v].yo-th-1,t,ColorToARGB(ink,la));
           }
        }
     }
   // 3. Strip borders and names.
   for(int k=0;k<g_zmark_n;k++)
     {
      int z=g_zocc[g_zvis[g_zmark[k].vis].occ].zone,x0=g_zmark[k].x0,x1=g_zmark[k].x1;
      if(x1<x0)continue;
      color ink=g_zact.zones[z].ink;
      if(g_zmark[k].shade)
         g_line_canvas.Rectangle(x0,g_zmark[k].y0,x1,g_zmark[k].y1-1,ColorToARGB(ink,(uchar)MathRound(255*MathMin(1.0,g_zmark[k].alpha*1.6+0.2))));
      if(g_zmark[k].tw==0)continue;
      int pad=4,tw=g_zmark[k].tw,th=g_line_canvas.TextHeight(g_zmark[k].text);
      if(g_zact.declutter && tw+2*pad>x1-x0+1)continue;
      int tx=!g_zmark[k].shade?x0+pad:(g_zact.zones[z].align==1?x1-pad-tw:(x0+x1+1)/2-tw/2);
      int lo=(int)MathMax(x0+pad,2),hi=(int)MathMin(x1-pad-tw,g_width-tw-2);
      if(hi>=lo)tx=Lim(tx,lo,hi);  // keep the name inside the visible part of its strip
      g_line_canvas.TextOut(tx,g_zmark[k].y0+(g_zmark[k].y1-g_zmark[k].y0-th)/2,g_zmark[k].text,ColorToARGB(ZoneTextInk(ink,g_zmark[k].alpha,g_zmark[k].shade)));
     }
   g_line_canvas.FontSet("Segoe UI",U(15));
  }
// Marker strip under the pointer (last drawn wins), or -1.
int FindZoneMarkAt(const int x,const int y)
  {
   for(int k=g_zmark_n-1;k>=0;k--)
      if(x>=g_zmark[k].x0 && x<=g_zmark[k].x1 && y>=g_zmark[k].y0 && y<g_zmark[k].y1)return k;
   return -1;
  }
void ZoneLineHit(const int x,const int y,const int yline,const int xa,const int xb,const int i,const int k,int &best,int &occ,int &kind)
  {
   if(yline==FP_OFF || x<(int)MathMin(xa,xb)-2 || x>(int)MathMax(xa,xb)+2)return;
   int d=(int)MathAbs(y-yline);
   if(d<best){best=d;occ=i;kind=k;}
  }
// What the pointer is on: 0 marker, 1 range high, 2 range low, 3 midline (50%),
// 4 opening price, 5 extended high, 6 extended low, 7 boundary line.
bool FindZoneAt(const int x,const int y,int &occ,int &kind)
  {
   occ=-1;kind=0;
   int k=FindZoneMarkAt(x,y);
   if(k>=0){occ=g_zvis[g_zmark[k].vis].occ;return true;}
   int best=4;
   for(int v=0;v<g_zvis_n;v++)
     {
      int i=g_zvis[v].occ,z=g_zocc[i].zone,x0=g_zvis[v].x0,x1=g_zvis[v].x1;
      bool range=g_zvis[v].yh!=FP_OFF && g_zvis[v].yl!=FP_OFF;
      if(range && x1>x0)
        {
         if(g_zact.zones[z].box){ZoneLineHit(x,y,g_zvis[v].yh,x0,x1,i,1,best,occ,kind);ZoneLineHit(x,y,g_zvis[v].yl,x0,x1,i,2,best,occ,kind);}
         if(g_zact.zones[z].midline)ZoneLineHit(x,y,(g_zvis[v].yh+g_zvis[v].yl)/2,x0,x1,i,3,best,occ,kind);
         if(g_zact.zones[z].extend && !g_zocc[i].live)
           {ZoneLineHit(x,y,g_zvis[v].yh,x1,g_zvis[v].xh,i,5,best,occ,kind);ZoneLineHit(x,y,g_zvis[v].yl,x1,g_zvis[v].xl,i,6,best,occ,kind);}
        }
      if(g_zact.zones[z].open_line>0)ZoneLineHit(x,y,g_zvis[v].yo,x0,g_zvis[v].xe,i,4,best,occ,kind);
     }
   if(occ>=0)return true;
   for(int v=0;v<g_zvis_n;v++)
     {
      int i=g_zvis[v].occ,z=g_zocc[i].zone;
      if(g_zact.zones[z].style>=5)continue;
      int ya=0,yb=g_height-1;
      if(!g_zact.lines_full && g_zvis[v].yh!=FP_OFF && g_zvis[v].yl!=FP_OFF){ya=g_zvis[v].yh;yb=g_zvis[v].yl;}
      if(y<ya-3 || y>yb+3)continue;
      if(MathAbs(x-g_zvis[v].x0)<=3 || (g_zvis[v].x1!=g_zvis[v].x0 && MathAbs(x-g_zvis[v].x1)<=3)){occ=i;kind=7;return true;}
     }
   return false;
  }
string ZoneDateText(const long ny)
  {
   int y=0,m=0,d=0;long day=FPFloorDiv(ny,86400);
   FPCivilFromDays(day,y,m,d);
   return g_dow_names[FPDow(day)]+" "+IntegerToString(y)+"."+FPTwo(m)+"."+FPTwo(d);
  }
void ZoneTip(const int i,const int kind,string &lines[],color &accent)
  {
   int z=g_zocc[i].zone,n=0;
   bool line=g_zocc[i].te==g_zocc[i].ts;
   string times=FPHHMM(g_zact.zones[z].start)+(line?"":" - "+FPHHMM(g_zact.zones[z].end));
   ArrayResize(lines,10);
   lines[n++]=Clip(g_zact.zones[z].name,40);
   if(kind>=1 && kind<=6)
     {
      // A single line of the zone: what it is, its price, and (for liquidity) whether it was taken.
      double price=kind==1 || kind==5?g_zocc[i].hi:(kind==2 || kind==6?g_zocc[i].lo:(kind==3?(g_zocc[i].hi+g_zocc[i].lo)/2:g_zocc[i].op));
      string what=kind==1?"Range high":(kind==2?"Range low":(kind==3?"50% of the range (midline)":(kind==4?"Opening price":(kind==5?"Range high, extended":"Range low, extended"))));
      lines[n++]=what;
      lines[n++]="Price\t"+DoubleToString(price,_Digits);
      if(kind==5 || kind==6)
        {
         datetime taken=kind==5?g_zocc[i].hi_taken:g_zocc[i].lo_taken;
         string status="Not taken yet";
         if(taken>0)
           {
            long ny=FPServerToNY((long)taken,g_zmode,g_zgmt);
            status="Taken "+FPHHMM((int)(FPFloorDiv(ny,60)%1440))+" New York";
            if(FPFloorDiv(ny,86400)!=FPFloorDiv((long)g_zocc[i].ny,86400))status+=", "+g_dow_names[FPDow(FPFloorDiv(ny,86400))];
           }
         lines[n++]="Status\t"+status;
        }
      if(kind==3)
        {
         lines[n++]="High\t"+DoubleToString(g_zocc[i].hi,_Digits);
         lines[n++]="Low\t"+DoubleToString(g_zocc[i].lo,_Digits);
        }
      lines[n++]=FPZGroupSingular(g_zact.zones[z].group)+"   "+ZoneDateText((long)g_zocc[i].ny);
      lines[n++]="New York\t"+times;
      ArrayResize(lines,n);accent=g_zact.zones[z].ink;
      return;
     }
   lines[n++]=FPZGroupSingular(g_zact.zones[z].group)+"   "+ZoneDateText((long)g_zocc[i].ny);
   lines[n++]="New York\t"+times;
   lines[n++]="Server\t"+TimeToString(g_zocc[i].ts,TIME_MINUTES)+(line?"":" - "+TimeToString(g_zocc[i].te,TIME_MINUTES));
   if(g_zocc[i].state==1)
     {
      if(!line)
        {
         lines[n++]="High\t"+DoubleToString(g_zocc[i].hi,_Digits);
         lines[n++]="Low\t"+DoubleToString(g_zocc[i].lo,_Digits);
         lines[n++]="Range\t"+DoubleToString((g_zocc[i].hi-g_zocc[i].lo)/_Point,0)+" pts";
        }
      lines[n++]="Open\t"+DoubleToString(g_zocc[i].op,_Digits);
     }
   datetime now=ZoneNow();
   string status=line?"Passed":"Ended";
   if(now<g_zocc[i].ts)status="Starts in "+FPDuration((long)(g_zocc[i].ts-now));
   else if(!line && now<g_zocc[i].te)status="Live, "+FPDuration((long)(g_zocc[i].te-now))+" left";
   lines[n++]="Status\t"+status;
   if(kind==0 && g_zeditor)lines[n++]="Drag up or down to place this marker";
   ArrayResize(lines,n);accent=g_zact.zones[z].ink;
  }

// ---- Zones window: Parameters, Visualization, Fill and Macros tabs, plus row popups
string Tick(const bool on){return on?"[x] ":"[ ] ";}
string ZStyleText(const int s){string n[]={"Solid","Dash","Dot","Dash-dot","D-d-dot","None"};return n[Lim(s,0,5)];}
string ZStyleItem(const int s){if(s>=5)return "None (no lines)";return g_style_names[Lim(s,0,4)];}
string ZLabelText(const int l){return l==0?"Off":(l==1?"Name":"N+time");}
string ZLabelItem(const int l){return l==0?"Off":(l==1?"Name":"Name + times");}
string ZMarkerText(const int m){string n[]={"Off","Below","Above","Bottom","Top"};return n[Lim(m,0,4)];}
// The chart shows the window's draft while it is open (live preview); OK/Apply commit it.
void ZonePreview(const bool rebuild)
  {
   g_zact=g_zeditor?g_zedit:g_zcfg;
   if(rebuild){g_zocc_dirty=true;g_zone_resolve=0;}
   g_dirty=true;
  }
void OpenZones()
  {
   if(g_editor){Status("Finish or cancel Properties first.");return;}
   if(g_drag!=0 || g_armed)CancelDrag();
   ClosePopup();g_list=false;g_zedit=g_zcfg;g_zeditor=true;g_zpage=0;
   ZonePreview(false);g_ui_dirty=true;
  }
void CloseZones()
  {if(g_zdrag)ZoneDragCancel();ClosePopup();g_zeditor=false;g_slider_drag=false;ZonePreview(true);g_ui_dirty=true;}
void ZEndEdit(const string name)
  {
   if(!g_zeditor || StringFind(name,UIS("Z."))!=0 || RegType(name)!=OBJ_EDIT)return;
   string key=StringSubstr(name,StringLen(UIS("Z."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   bool accepted=true,rebuild=false;
   if(StringFind(key,"Name")==0)
     {
      int i=(int)StringToInteger(StringSubstr(key,4));
      if(i>=0 && i<g_zedit.count){string t=text;StringTrimLeft(t);StringTrimRight(t);g_zedit.zones[i].name=StringLen(t)>0?StringSubstr(t,0,40):"Zone";}
     }
   else if(StringFind(key,"Start")==0 || StringFind(key,"End")==0)
     {
      bool start=StringFind(key,"Start")==0;
      int i=(int)StringToInteger(StringSubstr(key,start?5:3)),m=0;
      if(i>=0 && i<g_zedit.count && FPParseHHMM(text,m)){if(start)g_zedit.zones[i].start=m;else g_zedit.zones[i].end=m;rebuild=true;}
      else accepted=false;
     }
   else if(key=="Days"){if(Numeric(text)){g_zedit.days_back=Lim((int)StringToInteger(text),1,60);rebuild=true;}else accepted=false;}
   else if(key=="Gmt"){if(Numeric(text)){g_zedit.broker_gmt=Lim((int)StringToInteger(text),-12,14);rebuild=true;}else accepted=false;}
   else if(key=="Lead"){if(Numeric(text))g_zedit.alert_lead=Lim((int)StringToInteger(text),0,120);else accepted=false;}
   else if(key=="Opacity"){if(Numeric(text)){g_zedit.opacity=Lim((int)StringToInteger(text),0,100);PlaceOpacityThumb();}else accepted=false;}
   else return;
   if(!accepted){g_edit_error=true;Status("Invalid value; previous setting restored.");g_ui_dirty=true;}
   ZonePreview(rebuild);
  }
bool HarvestZoneEdits()
  {
   if(!g_zeditor)return true;
   g_edit_error=false;
   string prefix=UIS("Z.");
   for(int i=0;i<g_reg_count;i++)
      if(g_reg[i].type==OBJ_EDIT && StringFind(g_reg[i].name,prefix)==0)ZEndEdit(g_reg[i].name);
   return !g_edit_error;
  }
bool ApplyZones(const bool close)
  {
   if(!g_zeditor)return false;
   if(!HarvestZoneEdits())return false;
   FPZoneConfig previous=g_zcfg;g_zcfg=g_zedit;
   if(!SaveZones()){g_zcfg=previous;Status("Could not save zone settings. Check the Experts log.");return false;}
   Status("Zone settings saved for every chart using workspace \""+InpWorkspace+"\".");
   if(close)CloseZones();else {ClosePopup();ZonePreview(true);g_ui_dirty=true;}
   return true;
  }
void ToggleZonesShown()
  {
   g_zcfg.enabled=!g_zcfg.enabled;
   if(g_zeditor)g_zedit.enabled=g_zcfg.enabled;
   SaveZones();ZonePreview(true);
   if(g_zeditor)g_ui_dirty=true;
   g_zbutton_tip="";g_zone_tick=0; // refresh the button state right away
   Status(g_zcfg.enabled?"Sessions, killzones & macros shown.":"Sessions, killzones & macros hidden ("+InpZonesHotkey+" shows them).");
  }
void ZoneTestAlert()
  {
   long ny=FPServerToNY((long)ZoneNow(),g_zmode,g_zgmt);
   ZoneFireAlert("Zones",(int)(FPFloorDiv(ny,60)%1440),true);
  }
int ZoneFiltered(int &idx[])
  {
   ArrayResize(idx,g_zedit.count);int n=0;
   for(int i=0;i<g_zedit.count;i++)if(g_zfilter<0 || g_zedit.zones[i].group==g_zfilter)idx[n++]=i;
   return n;
  }
void ZonesParamsTab(const int x,int cy)
  {
   Check("Z.Master","Show sessions, killzones & macros ("+InpZonesHotkey+")",g_zedit.enabled,x+U(12),cy,330);cy+=U(28);
   Label("Z.GrpL","Groups",x+U(12),cy+U(4));
   int gx[]={70,164,258,368,450};
   int gw[]={92,92,108,80,94};
   for(int g=0;g<FPZ_GROUPS;g++)Check("Z.Grp"+IntegerToString(g),FPZGroupName(g),g_zedit.group_on[g],x+U(gx[g]),cy,gw[g]);
   cy+=U(28);
   Label("Z.DowL","Trading days",x+U(12),cy+U(4));
   for(int d=0;d<7;d++)
      Button("Z.Dow"+IntegerToString(d),g_dow_names[d],x+U(96+d*44),cy,42,22,(g_zedit.dow_mask&(1<<d))!=0?clrLightSteelBlue:clrWhite);
   Tooltip("Z.Dow0","A trading day ends at 17:00 New York: the Asian session opening on Sunday evening belongs to Monday.");
   cy+=U(28);
   Label("Z.DaysL","Days back",x+U(12),cy+U(4));Edit("Z.Days",IntegerToString(g_zedit.days_back),x+U(96),cy,44);
   Check("Z.Upcoming","Show today's upcoming zones",g_zedit.upcoming,x+U(152),cy,230);cy+=U(28);
   Label("Z.BrokerL","Broker time",x+U(12),cy+U(4));
   Button("Z.Broker",ZoneBrokerText(g_zedit.broker_mode)+" v",x+U(96),cy,180);
   Label("Z.GmtL","GMT+N, N =",x+U(284),cy+U(4));Edit("Z.Gmt",IntegerToString(g_zedit.broker_gmt),x+U(356),cy,40);
   Tooltip("Z.Broker","How your broker's server clock relates to New York time. Check the line below against your terminal clock.");
   cy+=U(26);
   datetime now=ZoneNow();long ny=FPServerToNY((long)now,g_zmode,g_zgmt);
   string sign=g_zgmt>=0?"+":"",dst=g_zmode==3?" with EU DST":(g_zmode==4?" with US DST":"");
   string model=g_zmode==1?"NY + 7 h":"GMT"+sign+IntegerToString(g_zgmt)+dst;
   Label("Z.Clock","Now: New York "+FPHHMM((int)(FPFloorDiv(ny,60)%1440))+" = server "+TimeToString(now,TIME_MINUTES)+"   ("+model+(g_zedit.broker_mode==0?", detected":"")+")",x+U(96),cy,clrDimGray);
   cy+=U(26);
   Label("Z.AlertL","Alerts",x+U(12),cy+U(4));
   Check("Z.Sound","Sound",g_zedit.alert_sound,x+U(96),cy,76);
   Check("Z.Push","Push to phone",g_zedit.alert_push,x+U(176),cy,124);
   Edit("Z.Lead",IntegerToString(g_zedit.alert_lead),x+U(306),cy,36);Label("Z.LeadL","min before",x+U(346),cy+U(4));
   Button("Z.Test","Test",x+U(424),cy,56);
   Tooltip("Z.Push","Needs your MetaQuotes ID in Tools > Options > Notifications. Switch alerts on per zone with its ... button.");
  }
void ZonesVisualTab(const int x,const int cy)
  {
   Label("Z.TfTitle","Show each group up to",x+U(12),cy);
   int ry=cy+U(24);
   for(int g=0;g<FPZ_GROUPS;g++)
     {
      string n=IntegerToString(g);
      Label("Z.TfG"+n,FPZGroupName(g),x+U(12),ry+U(4));
      Button("Z.TfDn"+n,"<",x+U(116),ry,24);
      Label("Z.TfV"+n,g_tf_names[Lim(g_zedit.group_tf[g],0,20)],x+U(148),ry+U(4));
      Button("Z.TfUp"+n,">",x+U(186),ry,24);
      ry+=U(26);
     }
   int rx=x+U(250),qy=cy;
   Label("Z.LinesL","Boundary lines",rx,qy+U(4));
   Button("Z.LinesFull","Full height",rx+U(96),qy,88,22,g_zedit.lines_full?clrLightSteelBlue:clrWhite);
   Button("Z.LinesBox","Zone range",rx+U(186),qy,88,22,!g_zedit.lines_full?clrLightSteelBlue:clrWhite);
   qy+=U(28);
   Label("Z.FsL","Label size",rx,qy+U(4));Button("Z.FsDn","-",rx+U(96),qy,24);
   Label("Z.FsV",IntegerToString(g_zedit.label_size)+" px",rx+U(126),qy+U(4));Button("Z.FsUp","+",rx+U(172),qy,24);
   qy+=U(28);
   Check("Z.Declutter","Hide labels that don't fit",g_zedit.declutter,rx,qy,250);qy+=U(27);
   Check("Z.Highlight","Highlight the live zone",g_zedit.highlight,rx,qy,250);qy+=U(27);
   Check("Z.Fade","Fade older days",g_zedit.fade_old,rx,qy,250);qy+=U(27);
   Check("Z.Hover","Hover info for zones",g_zedit.hover,rx,qy,250);
  }
void ZonesFillTab(const int x,int cy)
  {
   Check("Z.Fill","Enable zone fill",g_zedit.fill,x+U(12),cy,200);
   Check("Z.Gradient","Vertical gradient",g_zedit.gradient,x+U(250),cy,200);cy+=U(29);
   Label("Z.ModeL","Fill",x+U(12),cy+U(4));
   string modes[]={"Full height","Range box","Both"};int mw[]={92,86,60};int mx=x+U(60);
   for(int m=0;m<3;m++){Button("Z.Mode"+IntegerToString(m),modes[m],mx,cy,mw[m],22,g_zedit.fill_mode==m?clrLightSteelBlue:clrWhite);mx+=U(mw[m]+2);}
   Tooltip("Z.Mode1","A box from each zone's high to its low");
   cy+=U(32);
   Label("Z.OpacityLabel","Opacity %",x+U(12),cy+U(4));Edit("Z.Opacity",IntegerToString(g_zedit.opacity),x+U(84),cy,48);
   g_slider_x0=x+U(148);g_slider_x1=x+U(FPZ_PANEL_WIDTH-22);g_slider_y0=cy-U(2);g_slider_y1=cy+U(24);g_slider_on=true;
   Box("Z.OpTrack",g_slider_x0,cy+U(9),FPZ_PANEL_WIDTH-170,5,clrSilver);
   PlaceOpacityThumb();
   cy+=U(36);
   // How zone shading and Fib shading combine (all shading is blended, never painted over).
   Label("Z.CutL","Zones cut through Fib shading",x+U(12),cy+U(4));
   string cuts[]={"Off","Half","Clear"};int bx=x+U(250);
   for(int k=0;k<3;k++){Button("Z.Cut"+IntegerToString(k),cuts[k],bx,cy,62,22,g_zedit.cut==k?clrLightSteelBlue:clrWhite);bx+=U(64);}
   Tooltip("Z.Cut0","Zone shading is blended over Fib shading");
   Tooltip("Z.Cut1","Inside shaded zones, Fib shading is halved");
   Tooltip("Z.Cut2","Inside shaded zones, Fib shading is removed");
   cy+=U(29);
   Label("Z.FtfL","Fib shading on lower timeframes",x+U(12),cy+U(4));
   string ftf[]={"Full","Faint","Off"};bx=x+U(250);
   for(int k=0;k<3;k++){Button("Z.Ftf"+IntegerToString(k),ftf[k],bx,cy,62,22,g_zedit.fib_lower==k?clrLightSteelBlue:clrWhite);bx+=U(64);}
   Tooltip("Z.Ftf0","On charts below a Fib's own timeframe, its shading is drawn as set");
   Tooltip("Z.Ftf1","On charts below a Fib's own timeframe, its shading is drawn at a third of its opacity");
   Tooltip("Z.Ftf2","On charts below a Fib's own timeframe, its shading is not drawn (levels and labels stay)");
   cy+=U(32);
   Label("Z.FillNote","Each zone's own fill switch is under its ... button in the Macros tab.",x+U(12),cy,clrDimGray);
  }
void ZonesTableTab(const int x,const int y,int cy)
  {
   string chips[]={"All","Sessions","Killzones","Silver Bullet","Macros","Time lines"};int cw[]={36,66,66,86,58,72};int cx=x+U(12);
   for(int f=0;f<6;f++){Button("Z.Flt"+IntegerToString(f),chips[f],cx,cy,cw[f],22,g_zfilter==f-1?clrLightSteelBlue:clrWhite);cx+=U(cw[f]+2);}
   cy+=U(26);
   int cols[]={12,40,154,200,246,314,346,378,434};
   string heads[]={"On","Name","Start","End","Style","W","Col","Label","Marker"};
   for(int c=0;c<9;c++)Label("Z.Head"+IntegerToString(c),heads[c],x+U(cols[c]),cy);
   Tooltip("Z.Head2","New York time, HH:MM. Start = End draws one time line; End before Start runs past midnight.");
   Tooltip("Z.Head8","Shaded name strip below the low, above the high, or at the chart bottom/top. Overlapping zones nest.");
   cy+=U(21);
   int idx[];int n=ZoneFiltered(idx);
   int rows=(int)MathMax(1,g_rows-1),pages=(int)MathMax(1,(n+rows-1)/rows);
   g_zpage=Lim(g_zpage,0,pages-1);
   for(int r=0;r<rows;r++)
     {
      int k=g_zpage*rows+r;
      if(k>=n)break;
      int i=idx[k],ry=cy+U(r*24);string s=IntegerToString(i);
      Button("Z.On"+s,g_zedit.zones[i].enabled?"x":"",x+U(12),ry,26);
      Edit("Z.Name"+s,g_zedit.zones[i].name,x+U(40),ry,112);
      Edit("Z.Start"+s,FPHHMM(g_zedit.zones[i].start),x+U(154),ry,44);
      Edit("Z.End"+s,FPHHMM(g_zedit.zones[i].end),x+U(200),ry,44);
      Button("Z.Style"+s,ZStyleText(g_zedit.zones[i].style)+" v",x+U(246),ry,66);
      Button("Z.Width"+s,IntegerToString(g_zedit.zones[i].width)+" v",x+U(314),ry,30);
      Button("Z.Color"+s,"",x+U(346),ry,30,22,g_zedit.zones[i].ink);
      Button("Z.Label"+s,ZLabelText(g_zedit.zones[i].label)+" v",x+U(378),ry,54);
      Button("Z.Marker"+s,ZMarkerText(g_zedit.zones[i].marker)+" v",x+U(434),ry,66);
      Button("Z.More"+s,"...",x+U(502),ry,24);
      Tooltip("Z.More"+s,"Group, fill, range box, extend high/low, opening price line, alert");
      Button("Z.Remove"+s,Glyph(0xD7),x+U(528),ry,22);
     }
   if(n==0)Label("Z.Empty","No zones in this group. Click Add.",x+U(16),cy+U(4),clrDimGray);
   int fy=y+PanelHeight()-U(93);
   Button("Z.Add","Add",x+U(12),fy,52);Button("Z.Defaults","Defaults",x+U(66),fy,70);Button("Z.Sort","Sort by time",x+U(138),fy,92);
   Tooltip("Z.Defaults","Restore the default zone list: sessions, ICT killzones, Silver Bullet, macros and time lines");
   Button("Z.PageBack","<",x+U(270),fy,26);Button("Z.PageNext",">",x+U(298),fy,26);
   Label("Z.Page",IntegerToString(g_zpage+1)+" / "+IntegerToString(pages),x+U(332),fy+U(4));
  }
void BuildZonesPanel()
  {
   int x=g_panel_x,y=g_panel_y,W=FPZ_PANEL_WIDTH;
   Box("Z.Background",x,y,W,184+g_rows*24,clrWhiteSmoke);
   Label("Z.Title","Sessions, killzones & macros",x+U(10),y+U(7));
   Label("Z.Shared","Shared by all charts of workspace \""+Clip(InpWorkspace,16)+"\"",x+U(250),y+U(7),clrDimGray);
   string tabs[]={"Parameters","Visualization","Fill","Macros"};int widths[]={92,104,52,72};int tx=x+U(10);
   for(int t=0;t<4;t++){Button("Z.Tab"+IntegerToString(t),tabs[t],tx,y+U(30),widths[t],23,t==g_ztab?clrWhite:clrGainsboro);tx+=U(widths[t]+2);}
   int cy=y+U(64);
   if(g_ztab==0)ZonesParamsTab(x,cy);
   else if(g_ztab==1)ZonesVisualTab(x,cy);
   else if(g_ztab==2)ZonesFillTab(x,cy);
   else ZonesTableTab(x,y,cy);
   int by=y+PanelHeight()-U(31);
   Button("Z.Save","Save",x+U(W-172),by-U(30),72);Button("Z.Load","Load",x+U(W-98),by-U(30),72);
   Tooltip("Z.Save","Save these settings as a named preset");
   Tooltip("Z.Load","Load or delete a preset (ICT Forex and ICT Indices are built in)");
   Button("Z.OK","OK",x+U(W-246),by,72);Button("Z.Cancel","Cancel",x+U(W-172),by,72);Button("Z.Apply","Apply",x+U(W-98),by,72);
  }
void ZonesClick(const string key)
  {
   if(key!="Cancel")
     {
      // Read active edits before their focus-loss events or an Apply click race.
      if(!HarvestZoneEdits())return;
      if(g_ui_dirty){ClosePopup();BuildUI();}
     }
   if(key=="OK"){ApplyZones(true);return;}
   if(key=="Apply"){ApplyZones(false);return;}
   if(key=="Cancel"){CloseZones();return;}
   if(key=="Save"){PresetBrowser(true);return;}
   if(key=="Load"){PresetBrowser(false);return;}
   if(StringFind(key,"Tab")==0){ClosePopup();g_ztab=Lim((int)StringToInteger(StringSubstr(key,3)),0,3);g_ui_dirty=true;return;}
   if(key=="Broker"){Dropdown(13,-1);return;}
   if(key=="Test"){ZoneTestAlert();return;}
   if(StringFind(key,"Style")==0){Dropdown(10,(int)StringToInteger(StringSubstr(key,5)));return;}
   if(StringFind(key,"Width")==0){Dropdown(11,(int)StringToInteger(StringSubstr(key,5)));return;}
   if(StringFind(key,"Label")==0){Dropdown(12,(int)StringToInteger(StringSubstr(key,5)));return;}
   if(StringFind(key,"Color")==0){Palette(-1000-(int)StringToInteger(StringSubstr(key,5)));return;}
   if(StringFind(key,"Marker")==0){ZoneMarkerPopup((int)StringToInteger(StringSubstr(key,6)));return;}
   if(StringFind(key,"More")==0){ZoneMorePopup((int)StringToInteger(StringSubstr(key,4)));return;}
   bool rebuild=false;
   if(key=="Master"){g_zedit.enabled=!g_zedit.enabled;rebuild=true;}
   else if(StringFind(key,"Grp")==0){int g=Lim((int)StringToInteger(StringSubstr(key,3)),0,FPZ_GROUPS-1);g_zedit.group_on[g]=!g_zedit.group_on[g];rebuild=true;}
   else if(StringFind(key,"Dow")==0){g_zedit.dow_mask^=(1<<Lim((int)StringToInteger(StringSubstr(key,3)),0,6));rebuild=true;}
   else if(key=="Upcoming"){g_zedit.upcoming=!g_zedit.upcoming;rebuild=true;}
   else if(key=="Sound")g_zedit.alert_sound=!g_zedit.alert_sound;
   else if(key=="Push")g_zedit.alert_push=!g_zedit.alert_push;
   else if(StringFind(key,"TfDn")==0){int g=Lim((int)StringToInteger(StringSubstr(key,4)),0,FPZ_GROUPS-1);g_zedit.group_tf[g]=Lim(g_zedit.group_tf[g]-1,0,20);}
   else if(StringFind(key,"TfUp")==0){int g=Lim((int)StringToInteger(StringSubstr(key,4)),0,FPZ_GROUPS-1);g_zedit.group_tf[g]=Lim(g_zedit.group_tf[g]+1,0,20);}
   else if(key=="LinesFull")g_zedit.lines_full=true;
   else if(key=="LinesBox")g_zedit.lines_full=false;
   else if(key=="FsDn")g_zedit.label_size=Lim(g_zedit.label_size-1,8,24);
   else if(key=="FsUp")g_zedit.label_size=Lim(g_zedit.label_size+1,8,24);
   else if(key=="Declutter")g_zedit.declutter=!g_zedit.declutter;
   else if(key=="Highlight")g_zedit.highlight=!g_zedit.highlight;
   else if(key=="Fade")g_zedit.fade_old=!g_zedit.fade_old;
   else if(key=="Hover")g_zedit.hover=!g_zedit.hover;
   else if(key=="Fill")g_zedit.fill=!g_zedit.fill;
   else if(StringFind(key,"Mode")==0)g_zedit.fill_mode=Lim((int)StringToInteger(StringSubstr(key,4)),0,2);
   else if(key=="Gradient")g_zedit.gradient=!g_zedit.gradient;
   else if(StringFind(key,"Cut")==0)g_zedit.cut=Lim((int)StringToInteger(StringSubstr(key,3)),0,2);
   else if(StringFind(key,"Ftf")==0)g_zedit.fib_lower=Lim((int)StringToInteger(StringSubstr(key,3)),0,2);
   else if(StringFind(key,"Flt")==0){g_zfilter=Lim((int)StringToInteger(StringSubstr(key,3)),0,5)-1;g_zpage=0;}
   else if(StringFind(key,"On")==0)
     {int i=(int)StringToInteger(StringSubstr(key,2));if(i<0 || i>=g_zedit.count)return;g_zedit.zones[i].enabled=!g_zedit.zones[i].enabled;rebuild=true;}
   else if(StringFind(key,"Remove")==0)
     {
      int i=(int)StringToInteger(StringSubstr(key,6));
      if(i<0 || i>=g_zedit.count)return;
      for(int k=i;k<g_zedit.count-1;k++)g_zedit.zones[k]=g_zedit.zones[k+1];
      g_zedit.count--;rebuild=true;
     }
   else if(key=="Add")
     {
      if(g_zedit.count>=FPZ_MAX){Status("Zone limit reached ("+IntegerToString(FPZ_MAX)+").");return;}
      int g=g_zfilter>=0?g_zfilter:1;
      FPZoneSet(g_zedit.zones[g_zedit.count],"New "+FPZGroupSingular(g),540,g==4?540:600,g,clrDodgerBlue,true);
      g_zedit.count++;
      int idx[];int n=ZoneFiltered(idx);g_zpage=(n-1)/(int)MathMax(1,g_rows-1);rebuild=true;
     }
   else if(key=="Defaults"){FPZoneDefaultList(g_zedit,false);g_zpage=0;rebuild=true;Status("Default zone list restored. Apply or OK to keep it.");}
   else if(key=="Sort"){FPZSortByTime(g_zedit);rebuild=true;}
   else if(key=="PageBack")g_zpage=(int)MathMax(0,g_zpage-1);
   else if(key=="PageNext")g_zpage++;
   else return; // Unknown command: keep the panel (and any edit focus) as it is.
   ZonePreview(rebuild);g_ui_dirty=true;
  }
// ---- row popups (prefix Q.): marker placement and more options
void QButton(const string key,const string text,const int x,const int y,const int w,const bool on)
  {UIBase(Obj("Q."+key),OBJ_BUTTON,x,y,U(w),U(22),text,on?clrLightSteelBlue:clrWhite,clrBlack,410);}
void QLabel(const string key,const string text,const int x,const int y)
  {UIBase(Obj("Q."+key),OBJ_LABEL,x,y,0,0,text,clrWhite,clrBlack,410);}
void ZonePopupFrame(const int kind,const int i,const string source,const int w,const int h)
  {
   int ri=RegFind(UIS(source));
   ClosePopup();g_popup=kind;g_popup_row=i;g_popup_w=U(w);g_popup_h=U(h);
   g_popup_x=ri>=0?g_reg[ri].x+g_reg[ri].w-g_popup_w:g_panel_x+U(100);
   g_popup_y=ri>=0?g_reg[ri].y+g_reg[ri].h+U(2):g_panel_y+U(100);
   if(g_popup_y+g_popup_h>g_height && ri>=0)g_popup_y=g_reg[ri].y-g_popup_h-U(2);
   g_popup_x=Lim(g_popup_x,0,(int)MathMax(0,g_width-g_popup_w));g_popup_y=Lim(g_popup_y,0,(int)MathMax(0,g_height-g_popup_h));
  }
void ZoneMarkerPopupBuild()
  {
   int i=g_popup_row,px=g_popup_x,py=g_popup_y;
   if(i<0 || i>=g_zedit.count)return;
   UIBase(Obj("Q.BG"),OBJ_RECTANGLE_LABEL,px,py,g_popup_w,g_popup_h,"",clrWhiteSmoke,clrBlack,400);
   QLabel("Title","Marker - "+Clip(g_zedit.zones[i].name,34),px+U(10),py+U(7));
   QLabel("PosL","Position",px+U(10),py+U(34));
   string pos[]={"Off","Below low","Above high","Chart bottom","Chart top"};int pw[]={36,70,74,86,66};int bx=px+U(64);
   for(int p=0;p<5;p++){QButton("Pos"+IntegerToString(p),pos[p],bx,py+U(30),pw[p],g_zedit.zones[i].marker==p);bx+=U(pw[p]+2);}
   QLabel("AlL","Align",px+U(10),py+U(62));
   QButton("Al0","Centre",px+U(64),py+U(58),70,g_zedit.zones[i].align==0);
   QButton("Al1","Right",px+U(136),py+U(58),70,g_zedit.zones[i].align==1);
   QLabel("StL","Stack",px+U(222),py+U(62));
   QButton("St0","Auto",px+U(264),py+U(58),70,g_zedit.zones[i].stack==0);
   QButton("St1","Fixed",px+U(336),py+U(58),70,g_zedit.zones[i].stack==1);
   QLabel("DistL","Distance",px+U(10),py+U(90));
   QButton("DistDn","-",px+U(64),py+U(86),24,false);QLabel("DistV",IntegerToString(g_zedit.zones[i].distance)+" px",px+U(94),py+U(90));
   QButton("DistUp","+",px+U(140),py+U(86),24,false);
   QLabel("HL","Height",px+U(190),py+U(90));
   QButton("HDn","-",px+U(240),py+U(86),24,false);QLabel("HV",IntegerToString(g_zedit.zones[i].height)+" px",px+U(270),py+U(90));
   QButton("HUp","+",px+U(316),py+U(86),24,false);
   QLabel("OpL","Opacity",px+U(10),py+U(118));
   QButton("OpDn","-",px+U(64),py+U(114),24,false);QLabel("OpV",IntegerToString(g_zedit.zones[i].mopacity)+" %",px+U(94),py+U(118));
   QButton("OpUp","+",px+U(140),py+U(114),24,false);
   QLabel("Hint","Distance: from the low/high, or from the chart edge.",px+U(10),py+U(146));
   QLabel("Hint2","Auto avoids overlaps; Fixed stays put. Or drag it on the chart.",px+U(10),py+U(164));
   QButton("Done","Done",px+U(340),py+U(190),70,false);
   ChartRedraw();
  }
void ZoneMarkerPopup(const int i)
  {
   if(!g_zeditor || i<0 || i>=g_zedit.count)return;
   ZonePopupFrame(14,i,"Z.Marker"+IntegerToString(i),420,220);
   ZoneMarkerPopupBuild();
  }
void ZoneMorePopupBuild()
  {
   int i=g_popup_row,px=g_popup_x,py=g_popup_y;
   if(i<0 || i>=g_zedit.count)return;
   UIBase(Obj("Q.BG"),OBJ_RECTANGLE_LABEL,px,py,g_popup_w,g_popup_h,"",clrWhiteSmoke,clrBlack,400);
   QLabel("Title","Options - "+Clip(g_zedit.zones[i].name,34),px+U(10),py+U(7));
   QLabel("GL","Group",px+U(10),py+U(34));
   int gw[]={64,64,88,56,70};int bx=px+U(64);
   for(int g=0;g<FPZ_GROUPS;g++){QButton("G"+IntegerToString(g),FPZGroupSingular(g),bx,py+U(30),gw[g],g_zedit.zones[i].group==g);bx+=U(gw[g]+2);}
   QButton("Fill",Tick(g_zedit.zones[i].fill)+"Fill this zone",px+U(10),py+U(58),190,false);
   QButton("Box",Tick(g_zedit.zones[i].box)+"Range box (high/low)",px+U(206),py+U(58),190,false);
   QButton("Mid",Tick(g_zedit.zones[i].midline)+"50% line (midline)",px+U(10),py+U(86),190,false);
   QButton("Extend",Tick(g_zedit.zones[i].extend)+"Extend high/low until taken",px+U(206),py+U(86),190,false);
   QButton("Alert",Tick(g_zedit.zones[i].alert)+"Alert when it starts",px+U(10),py+U(114),190,false);
   QLabel("OL","Opening price line",px+U(10),py+U(150));
   string ol[]={"Off","To zone end","To end of day"};int ow[]={40,90,96};bx=px+U(130);
   for(int o=0;o<3;o++){QButton("Open"+IntegerToString(o),ol[o],bx,py+U(146),ow[o],g_zedit.zones[i].open_line==o);bx+=U(ow[o]+2);}
   QLabel("Hint","Hover these lines for their prices. Alerts: see Parameters.",px+U(10),py+U(180));
   QButton("Done","Done",px+U(340),py+U(204),70,false);
   ChartRedraw();
  }
void ZoneMorePopup(const int i)
  {
   if(!g_zeditor || i<0 || i>=g_zedit.count)return;
   ZonePopupFrame(15,i,"Z.More"+IntegerToString(i),420,234);
   ZoneMorePopupBuild();
  }
void ZonePopupClick(const string name)
  {
   string key=StringSubstr(name,StringLen(Obj("Q.")));
   int i=g_popup_row;
   if(!g_zeditor || i<0 || i>=g_zedit.count){ClosePopup();return;}
   if(key=="Done"){ClosePopup();g_ui_dirty=true;return;}
   if(g_popup==14)
     {
      if(StringFind(key,"Pos")==0)g_zedit.zones[i].marker=Lim((int)StringToInteger(StringSubstr(key,3)),0,4);
      else if(StringFind(key,"Al")==0)g_zedit.zones[i].align=Lim((int)StringToInteger(StringSubstr(key,2)),0,1);
      else if(StringFind(key,"St")==0)g_zedit.zones[i].stack=Lim((int)StringToInteger(StringSubstr(key,2)),0,1);
      else if(key=="DistDn")g_zedit.zones[i].distance=Lim(g_zedit.zones[i].distance-2,0,400);
      else if(key=="DistUp")g_zedit.zones[i].distance=Lim(g_zedit.zones[i].distance+2,0,400);
      else if(key=="HDn")g_zedit.zones[i].height=Lim(g_zedit.zones[i].height-2,8,60);
      else if(key=="HUp")g_zedit.zones[i].height=Lim(g_zedit.zones[i].height+2,8,60);
      else if(key=="OpDn")g_zedit.zones[i].mopacity=Lim(g_zedit.zones[i].mopacity-10,0,100);
      else if(key=="OpUp")g_zedit.zones[i].mopacity=Lim(g_zedit.zones[i].mopacity+10,0,100);
      else return;
      SetText(UIS("Z.Marker"+IntegerToString(i)),ZMarkerText(g_zedit.zones[i].marker)+" v");
      ZonePreview(false);ZoneMarkerPopupBuild();
     }
   else if(g_popup==15)
     {
      bool rebuild=false;
      if(StringFind(key,"G")==0 && StringLen(key)==2){g_zedit.zones[i].group=Lim((int)StringToInteger(StringSubstr(key,1)),0,4);rebuild=true;}
      else if(key=="Fill")g_zedit.zones[i].fill=!g_zedit.zones[i].fill;
      else if(key=="Box")g_zedit.zones[i].box=!g_zedit.zones[i].box;
      else if(key=="Mid")g_zedit.zones[i].midline=!g_zedit.zones[i].midline;
      else if(key=="Extend"){g_zedit.zones[i].extend=!g_zedit.zones[i].extend;rebuild=true;}
      else if(key=="Alert")g_zedit.zones[i].alert=!g_zedit.zones[i].alert;
      else if(StringFind(key,"Open")==0)g_zedit.zones[i].open_line=Lim((int)StringToInteger(StringSubstr(key,4)),0,2);
      else return;
      ZonePreview(rebuild);ZoneMorePopupBuild();
     }
   g_need_redraw=true;
  }
// ---- zones presets (same dialog as the Fib presets; two built-ins are generated)
bool ZoneBuiltin(const string name){return name==FPZ_BUILTIN_FX || name==FPZ_BUILTIN_IDX;}
void ZonePresetAction()
  {
   string filename="FibonacciPro\\Presets\\"+g_preset_name+".fzp";
   if(g_preset_save)
     {
      if(ZoneBuiltin(g_preset_name)){PresetMessage("Built-in presets are read-only; choose another name.");return;}
      if(!HarvestZoneEdits()){PresetMessage("Correct the invalid values before saving.");return;}
      if(!FPZWriteFile(filename,g_zedit)){PresetMessage("Could not save preset. Check Experts log.");Print("Fibonacci Pro zones preset write error: ",GetLastError());return;}
      if(!ApplyZones(false)){ClosePopup();Status("Preset saved; applying the zone settings failed.");return;}
      Status("Saved zones preset: "+g_preset_name+".");
      return;
     }
   FPZoneConfig loaded;
   if(ZoneBuiltin(g_preset_name))FPZoneDefaults(loaded,g_preset_name==FPZ_BUILTIN_IDX);
   else if(!FPZReadFile(filename,loaded) && !FPZReadFile(filename+".bak",loaded)){PresetMessage("Preset missing or invalid; current settings retained.");return;}
   // Broker time belongs to this terminal, not to a preset.
   loaded.broker_mode=g_zedit.broker_mode;loaded.broker_gmt=g_zedit.broker_gmt;
   loaded.cut=g_zedit.cut;loaded.fib_lower=g_zedit.fib_lower;   // how zones and Fib shading combine stays as set
   g_zedit=loaded;g_zpage=0;ClosePopup();ZonePreview(true);g_ui_dirty=true;
   Status("Loaded "+g_preset_name+". Apply or OK to keep it; Cancel to revert.");
  }
// ---- drag a marker strip to place it (only while the Zones window is open)
// A marker strip under the pointer that a press would drag (Zones window open, no popup).
bool ZoneDragHot(const int x,const int y)
  {return g_zeditor && !g_hidden && g_popup==0 && !g_editor && FindZoneMarkAt(x,y)>=0;}
bool ZoneDragBegin(const int x,const int y)
  {
   if(!g_zeditor || g_hidden || g_popup!=0)return false;
   int k=FindZoneMarkAt(x,y);
   if(k<0)return false;
   int v=g_zmark[k].vis,z=g_zocc[g_zvis[v].occ].zone;
   if(z<0 || z>=g_zedit.count)return false;
   g_zdrag=true;g_zdrag_zone=z;g_zdrag_anchor=g_zmark[k].anchor;
   g_zdrag_dy=y-g_zmark[k].y0;g_zdrag_h=g_zmark[k].y1-g_zmark[k].y0;
   g_zdrag_base=g_zdrag_anchor==1?g_zvis[v].yl:(g_zdrag_anchor==2?g_zvis[v].yh:0);
   g_zdrag_old_distance=g_zedit.zones[z].distance;g_zdrag_old_stack=g_zedit.zones[z].stack;
   g_zdrag_press_y=y;g_zdrag_moved=false;
   HoldScroll();
   return true;
  }
// The strip follows the pointer; its zone becomes Fixed at the matching distance, so the
// same placement applies on every day (relative to each day's low/high or the chart edge).
void ZoneDragMove(const int x,const int y)
  {
   if(!g_zdrag || g_zdrag_zone<0 || g_zdrag_zone>=g_zedit.count)return;
   if(!g_zdrag_moved){if(MathAbs(y-g_zdrag_press_y)<3)return;g_zdrag_moved=true;}
   int top=y-g_zdrag_dy,d=0;
   if(g_zdrag_anchor==1)d=top-g_zdrag_base;
   else if(g_zdrag_anchor==2)d=g_zdrag_base-(top+g_zdrag_h);
   else if(g_zdrag_anchor==3)d=g_height-(top+g_zdrag_h);
   else d=top;
   d=Lim(d,0,400);
   if(d==g_zedit.zones[g_zdrag_zone].distance && g_zedit.zones[g_zdrag_zone].stack==1)return;
   g_zedit.zones[g_zdrag_zone].distance=d;g_zedit.zones[g_zdrag_zone].stack=1;
   ZonePreview(false);
  }
void ZoneDragEnd()
  {
   if(!g_zdrag)return;
   g_zdrag=false;ReleaseScroll();g_ui_dirty=true;
   if(g_zdrag_moved && g_zdrag_zone>=0 && g_zdrag_zone<g_zedit.count)
      Status(g_zedit.zones[g_zdrag_zone].name+" marker placed ("+IntegerToString(g_zedit.zones[g_zdrag_zone].distance)+" px, fixed). Apply or OK to keep it.");
  }
void ZoneDragCancel()
  {
   if(!g_zdrag)return;
   if(g_zdrag_zone>=0 && g_zdrag_zone<g_zedit.count)
     {g_zedit.zones[g_zdrag_zone].distance=g_zdrag_old_distance;g_zedit.zones[g_zdrag_zone].stack=g_zdrag_old_stack;}
   g_zdrag=false;ReleaseScroll();ZonePreview(false);
  }

// ---------------------------------------------------------------- hover information
bool EnsureTip()
  {
   if(g_tip_ready)return true;
   g_tip_cw=U(440);g_tip_ch=U(170);
   if(!g_tip.CreateBitmapLabel(0,0,Obj("Tip"),0,0,g_tip_cw,g_tip_ch,COLOR_FORMAT_ARGB_NORMALIZE))return false;
   CanvasObject(Obj("Tip"),false,500);
   ObjectSetInteger(0,Obj("Tip"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   g_tip.FontSet("Segoe UI",U(14));
   g_tip_ready=true;g_tip_visible=false;g_tip_key="";g_tip_x=FP_OFF;g_tip_y=FP_OFF;
   return true;
  }
bool HideTip()
  {
   if(!g_tip_visible)return false;
   ObjectSetInteger(0,Obj("Tip"),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);g_tip_visible=false;
   return true;
  }
// Lines may hold "label<TAB>value" pairs, drawn as two aligned columns.
void DrawTip(string &lines[],const color accent)
  {
   int n=ArraySize(lines),pad=U(7),gap=U(12),bar=U(3);
   int lh=g_tip.TextHeight("Ag")+U(2),c1=0,c2=0,full=0;
   for(int i=0;i<n;i++)
     {
      int tab=StringFind(lines[i],"\t");
      if(tab<0){full=(int)MathMax(full,g_tip.TextWidth(lines[i]));continue;}
      c1=(int)MathMax(c1,g_tip.TextWidth(StringSubstr(lines[i],0,tab)));
      c2=(int)MathMax(c2,g_tip.TextWidth(StringSubstr(lines[i],tab+1)));
     }
   int inner=(int)MathMax(full,(c1>0 || c2>0)?c1+gap+c2:0);
   int w=Lim(bar+pad*2+inner,U(60),g_tip_cw),h=Lim(pad*2+n*lh,U(20),g_tip_ch);
   uint fgc=ColorToARGB(g_chart_fg),muted=ColorToARGB(FPBlend(g_chart_fg,g_chart_bg,.45));
   g_tip.Erase(0);
   g_tip.FillRectangle(0,0,w-1,h-1,ColorToARGB(g_chart_bg,240));
   g_tip.Rectangle(0,0,w-1,h-1,ColorToARGB(FPBlend(g_chart_fg,g_chart_bg,.55)));
   g_tip.FillRectangle(1,1,bar,h-2,ColorToARGB(accent));
   int tx=bar+pad,ty=pad;
   for(int i=0;i<n;i++)
     {
      int tab=StringFind(lines[i],"\t");
      if(tab<0)g_tip.TextOut(tx,ty,lines[i],fgc);
      else {g_tip.TextOut(tx,ty,StringSubstr(lines[i],0,tab),muted);g_tip.TextOut(tx+c1+gap,ty,StringSubstr(lines[i],tab+1),fgc);}
      ty+=lh;
     }
   g_tip.Update(false);
   // Only the used part of the bitmap is shown (and hit-tested).
   ObjectSetInteger(0,Obj("Tip"),OBJPROP_XSIZE,w);ObjectSetInteger(0,Obj("Tip"),OBJPROP_YSIZE,h);
   g_tip_w=w;g_tip_h=h;
  }
bool ShowTip(const int mx,const int my,string &lines[],const color accent)
  {
   if(!EnsureTip())return false;
   string key=IntegerToString((int)accent);
   for(int i=0;i<ArraySize(lines);i++)key+="\n"+lines[i];
   bool changed=false;
   if(key!=g_tip_key){DrawTip(lines,accent);g_tip_key=key;changed=true;}
   int x=mx+U(16),y=my+U(18);
   if(x+g_tip_w>g_width-2)x=mx-U(12)-g_tip_w;
   if(y+g_tip_h>g_height-2)y=my-U(10)-g_tip_h;
   x=Lim(x,0,(int)MathMax(0,g_width-g_tip_w));y=Lim(y,0,(int)MathMax(0,g_height-g_tip_h));
   if(x!=g_tip_x){ObjectSetInteger(0,Obj("Tip"),OBJPROP_XDISTANCE,x);g_tip_x=x;changed=true;}
   if(y!=g_tip_y){ObjectSetInteger(0,Obj("Tip"),OBJPROP_YDISTANCE,y);g_tip_y=y;changed=true;}
   if(!g_tip_visible){ObjectSetInteger(0,Obj("Tip"),OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);g_tip_visible=true;changed=true;}
   return changed; // The chart is redrawn only when the tip actually changed.
  }
bool FindFibAt(const int x,const int y,int &slot,int &level)
  {
   int tol=U(4),best=tol+1;slot=-1;level=-1;
   for(int i=g_count-1;i>=0;i--)
     {
      if(!g_geo[i].valid || x<g_geo[i].l-tol || x>g_geo[i].r+tol)continue;
      for(int k=0;k<g_geo[i].count;k++)
        {
         int ly=g_geo[i].ly[k];
         if(ly==FP_OFF)continue;
         int d=(int)MathAbs(y-ly);
         if(d<best || (d==best && i==g_selected)){best=d;slot=i;level=k;}
        }
     }
   return slot>=0;
  }
// Candle under the pointer: inside its body/wick column and between its high and low.
bool FindCandleAt(const int x,const int y,int &shift)
  {
   datetime t=0;double p=0;int sub=-1;
   if(!ChartXYToTimePrice(0,x,y,sub,t,p) || sub!=0)return false;
   int center=iBarShift(_Symbol,PERIOD_CURRENT,t,false);
   if(center<0)return false;
   int spacing=1<<(int)Lim((int)g_view_scale,0,5);
   int half=(int)MathMax(1,MathRound(spacing*.45)),tol=(int)MathMax(2,U(2));
   int best=-1,best_d=half+1;
   for(int k=center-1;k<=center+1;k++)
     {
      if(k<0)continue;
      datetime bt=iTime(_Symbol,PERIOD_CURRENT,k);if(bt==0)continue;
      int cx=0,yh=0,ignore=0,yl=0;
      if(!XY(bt,iHigh(_Symbol,PERIOD_CURRENT,k),cx,yh) || !XY(bt,iLow(_Symbol,PERIOD_CURRENT,k),ignore,yl))continue;
      int d=(int)MathAbs(x-cx);
      if(d<best_d && y>=yh-tol && y<=yl+tol){best_d=d;best=k;}
     }
   shift=best;
   return best>=0;
  }
void FibTip(FPSetup &s,const int k,string &lines[],color &accent)
  {
   double price=FPLevelPrice(s.pa,s.pb,s.levels[k].value);
   int n=0,source=TFIndex(s.source_tf);ArrayResize(lines,7);
   lines[n++]=Clip(s.name,44);
   if(StringLen(s.description)>0)lines[n++]=Clip(s.description,56);
   lines[n++]="Level\t"+PercentText(s.levels[k].value);
   if(StringLen(s.levels[k].description)>0 && s.levels[k].description!=FP_DEFAULT_TEXT)lines[n++]="Label\t"+Clip(LevelText(s.levels[k],price),40);
   lines[n++]="Price\t"+DoubleToString(price,_Digits);
   lines[n++]="Anchored on\t"+(source>=0?g_tf_names[source]:"?");
   ArrayResize(lines,n);accent=s.levels[k].ink;
  }
void CandleTip(const int shift,string &lines[],color &accent)
  {
   double o=iOpen(_Symbol,PERIOD_CURRENT,shift),h=iHigh(_Symbol,PERIOD_CURRENT,shift),l=iLow(_Symbol,PERIOD_CURRENT,shift),c=iClose(_Symbol,PERIOD_CURRENT,shift);
   // Instrument and timeframe sit under the date and time to keep the tooltip narrow.
   ArrayResize(lines,7);
   lines[0]=TimeToString(iTime(_Symbol,PERIOD_CURRENT,shift),TIME_DATE|TIME_MINUTES);
   lines[1]=_Symbol+"  "+g_tf_names[g_tf];
   lines[2]="Open\t"+DoubleToString(o,_Digits);
   lines[3]="High\t"+DoubleToString(h,_Digits);
   lines[4]="Low\t"+DoubleToString(l,_Digits);
   lines[5]="Close\t"+DoubleToString(c,_Digits);
   lines[6]="Range\t"+DoubleToString((h-l)/_Point,0)+" pts";
   accent=c>=o?clrSeaGreen:clrCrimson;
  }
bool UpdateHover()
  {
   g_hover_pending=false;
   int x=g_mouse_x,y=g_mouse_y;
   bool allowed=(InpHoverCandleInfo || InpHoverFibInfo || (g_zact.enabled && g_zact.hover)) && g_mouse_in && !g_prev_down && g_drag==0 && !g_toolbar_drag
                && !g_slider_drag && !g_zdrag && g_picker_drag==0 && g_popup==0 && !HitUI(x,y);
   if(!allowed)return HideTip();
   string lines[];color accent=clrNONE;int slot=-1,level=-1,shift=-1,zocc=-1,zkind=0;
   if(InpHoverFibInfo && FindFibAt(x,y,slot,level))
     {if(g_editor && slot==g_selected)FibTip(g_edit,level,lines,accent);else FibTip(g_sets[slot],level,lines,accent);}
   else if(g_zact.enabled && g_zact.hover && FindZoneAt(x,y,zocc,zkind))ZoneTip(zocc,zkind,lines,accent);
   else if(InpHoverCandleInfo && FindCandleAt(x,y,shift))CandleTip(shift,lines,accent);
   else return HideTip();
   return ShowTip(x,y,lines,accent);
  }

bool HitUI(const int x,const int y)
  {
   if(g_hidden)return false;
   if(y>=g_toolbar_y && y<=g_toolbar_y+U(FP_TOOLBAR_HEIGHT) && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH))return true;
   if(g_popup==4 && x>=g_popup_x && x<=g_popup_x+U(360) && y>=g_popup_y && y<=g_popup_y+U(326))return true;
   if(g_popup==3 && x>=g_popup_x && x<=g_popup_x+U(360) && y>=g_popup_y && y<=g_popup_y+U(354))return true;
   if((g_popup==1 || g_popup==2 || g_popup>=5) && x>=g_popup_x && x<=g_popup_x+g_popup_w && y>=g_popup_y && y<=g_popup_y+g_popup_h)return true;
   if(g_list && !g_editor && x>=g_panel_x && x<=g_panel_x+U(FP_LIST_WIDTH) && y>=g_panel_y && y<=g_panel_y+ListHeight())return true;
   if(g_zeditor && x>=g_panel_x && x<=g_panel_x+U(FPZ_PANEL_WIDTH) && y>=g_panel_y && y<=g_panel_y+PanelHeight())return true;
   return g_editor && x>=g_panel_x && x<=g_panel_x+U(FP_PANEL_WIDTH) && y>=g_panel_y && y<=g_panel_y+PanelHeight();
  }
double SegmentDistance(const int x,const int y,const int xa,const int ya,const int xb,const int yb)
  {
   double dx=(double)xb-xa,dy=(double)yb-ya,length=dx*dx+dy*dy;
   double t=length>0?MathMax(0,MathMin(1,((x-xa)*dx+(y-ya)*dy)/length)):0;
   return MathSqrt(MathPow(x-(xa+t*dx),2)+MathPow(y-(ya+t*dy),2));
  }
// Handles: 2/3 anchors, 4/5 left/right drawers, 6 move, 7 line origin, 8 line body.
int HitHandle(FPSetup &s,const int slot,const int x,const int y)
  {
   if(!g_geo[slot].valid)return 0;
   int tol=U(7),line=g_geo[slot].line;
   if(s.hline && line>=0 && g_geo[slot].ly[line]!=FP_OFF)
     {
      int ly=g_geo[slot].ly[line];
      if(!s.anchors_locked && MathAbs(x-OriginX(slot))<=tol && MathAbs(y-ly)<=tol)return 7;
      if(!s.ray_right && MathAbs(x-Lim(g_geo[slot].xr,5,g_width-6))<=tol && MathAbs(y-ly)<=tol)return 5;
      return 0;
     }
   int xa=g_geo[slot].xa,ya=g_geo[slot].ya,xb=g_geo[slot].xb,yb=g_geo[slot].yb;
   int mid=Lim((int)(((long)ya+yb)/2),5,g_height-6);
   // Anchors take priority if a drawer and anchor overlap on a small drawing.
   if(!s.anchors_locked)
     {
      if(MathAbs(x-xa)<=tol && MathAbs(y-ya)<=tol)return 2;
      if(MathAbs(x-xb)<=tol && MathAbs(y-yb)<=tol)return 3;
     }
   if(MathAbs(x-Lim(g_geo[slot].xl,5,g_width-6))<=tol && MathAbs(y-mid)<=tol)return 4;
   if(MathAbs(x-Lim(g_geo[slot].xr,5,g_width-6))<=tol && MathAbs(y-mid)<=tol)return 5;
   if(!s.anchors_locked && MathAbs(x-(int)(((long)xa+xb)/2))<=tol && MathAbs(y-(int)(((long)ya+yb)/2))<=tol)return 6;
   return 0;
  }
bool LineBodyHit(FPSetup &s,const int slot,const int x,const int y)
  {
   int line=g_geo[slot].line;
   if(!g_geo[slot].valid || !s.hline || s.anchors_locked || line<0 || g_geo[slot].ly[line]==FP_OFF)return false;
   int tol=U(5);
   return x>=g_geo[slot].l-tol && x<=g_geo[slot].r+tol && MathAbs(y-g_geo[slot].ly[line])<=tol;
  }
bool HitSetup(FPSetup &s,const int slot,const int x,const int y)
  {
   if(!g_geo[slot].valid)return false;
   int tol=U(5);
   if(s.diagonal && SegmentDistance(x,y,g_geo[slot].xa,g_geo[slot].ya,g_geo[slot].xb,g_geo[slot].yb)<=tol)return true;
   if(x<g_geo[slot].l-tol || x>g_geo[slot].r+tol)return false;
   for(int i=0;i<g_geo[slot].count;i++)
     {int ly=g_geo[slot].ly[i];if(ly!=FP_OFF && MathAbs(y-ly)<=tol)return true;}
   return false;
  }
void Arm()
  {
   if(g_drag!=0)CancelDrag();
   if(g_count>=MaxSetups()){Status("Drawing limit reached ("+IntegerToString(MaxSetups())+"). Delete a drawing or raise InpMaximumSetups.");return;}
   CloseEditor();g_armed=true;HoldScroll();
   // Another program may have switched mouse-move events off; drawing depends on them.
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   Status("Drag for a Fib with the last used levels; single-click for a horizontal line. Esc cancels.");
  }
void CancelDrag()
  {
   if(g_zdrag)ZoneDragCancel();
   if(g_toolbar_drag){g_toolbar_drag=false;g_toolbar_moved=false;SaveLayout();}
   if(g_created>=0 && g_created<g_count){g_count--;g_selected=g_previous_selection;}
   else if(g_drag!=0 && g_selected>=0 && g_selected<g_count)g_sets[g_selected]=g_drag_backup;
   g_created=-1;g_drag=0;g_armed=false;g_slider_drag=false;ReleaseScroll();g_dirty=true;g_ui_dirty=true;
  }
bool HitZonesButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-92) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-32) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
bool HitCloseButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-28) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-8) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
void BeginMouse(const int x,const int y)
  {
   g_panel_key_held=false;g_duplicate_key_held=false;
   if(!HitCloseButton(x,y) && !HitZonesButton(x,y) && !g_hidden && !g_armed && g_drag==0 && g_popup==0 && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH) && y>=g_toolbar_y && y<g_toolbar_y+U(21))
     {g_toolbar_drag=true;g_toolbar_moved=false;g_toolbar_dx=x-g_toolbar_x;g_toolbar_dy=y-g_toolbar_y;HoldScroll();return;}
   if(HitUI(x,y))return;
   if(g_popup!=0){ClosePopup();return;}
   if(g_editor)return; // Finish/cancel properties before changing chart anchors.
   datetime t=0;double p=0;
   if(g_armed)
     {
      if(!Snap(x,y,(ENUM_TIMEFRAMES)_Period,t,p,InpSnapRadiusPixels)){Status("Choose a point inside the main chart window.");return;}
      if(g_count>=MaxSetups()){CancelDrag();Status("Drawing limit reached ("+IntegerToString(MaxSetups())+"). Delete a drawing or raise InpMaximumSetups.");return;}
      g_previous_selection=g_selected;g_created=g_count;g_selected=g_count;g_count++;
      NewSetup(g_sets[g_selected]);g_sets[g_selected].ta=t;g_sets[g_selected].tb=t;g_sets[g_selected].pa=p;g_sets[g_selected].pb=p;
      g_sets[g_selected].left=t;g_sets[g_selected].right=t+(datetime)PeriodSeconds();
      // Whatever visibility the template has, the new drawing is shown where it is drawn.
      g_sets[g_selected].visible_mask|=(long)1<<g_tf;
      g_drag=1;g_drag_x=x;g_drag_y=y;g_dirty=true;return;
     }
   // With the Zones window open, pressing a marker strip drags it into place.
   if(ZoneDragBegin(x,y))return;
   ComputeAllGeo(); // Hit-test against the exact current projection.
   ulong now=GetTickCount64();
   if(g_selected>=0 && g_selected<g_count)
     {
      int handle=HitHandle(g_sets[g_selected],g_selected,x,y);
      if(handle>0 && Point(x,y,t,p))
        {
         g_drag=handle;g_drag_backup=g_sets[g_selected];g_drag_time=t;g_drag_price=p;g_drag_x=x;g_drag_y=y;HoldScroll();return;
        }
      if(LineBodyHit(g_sets[g_selected],g_selected,x,y) && Point(x,y,t,p))
        {
         // Double-click still opens the properties of a horizontal line.
         if(g_last_hit==g_selected && now-g_last_down<400){g_last_down=0;OpenEditor();return;}
         g_last_hit=g_selected;g_last_down=now;
         g_drag=8;g_drag_backup=g_sets[g_selected];g_drag_time=t;g_drag_price=p;g_drag_x=x;g_drag_y=y;HoldScroll();return;
        }
     }
   int hit=-1;
   if(g_selected>=0 && g_selected<g_count && HitSetup(g_sets[g_selected],g_selected,x,y))hit=g_selected;
   else for(int i=g_count-1;i>=0;i--)if(HitSetup(g_sets[i],i,x,y)){hit=i;break;}
   bool twice=hit>=0 && hit==g_last_hit && now-g_last_down<400;
   if(hit!=g_selected){g_dirty=true;g_ui_dirty=true;g_list_follow=true;}
   g_selected=hit;g_last_hit=hit;g_last_down=now;
   if(twice)OpenEditor();
  }
void MoveToolbar(const int x,const int y)
  {
   int tx=Lim(x-g_toolbar_dx,0,(int)MathMax(0,g_width-U(FP_TOOLBAR_WIDTH))),ty=Lim(y-g_toolbar_dy,0,(int)MathMax(0,g_height-U(FP_TOOLBAR_HEIGHT)));
   if(tx==g_toolbar_x && ty==g_toolbar_y)return;
   g_toolbar_moved=true;
   g_toolbar_x=tx;g_toolbar_y=ty;g_toolbar_lx=tx/g_scale;g_toolbar_ly=ty/g_scale;
   // Positions are recomputed and only moved objects receive commands; no object reads.
   BuildToolbar();if(g_status_shown)UpdateStatusObjects(GetTickCount64());
   ChartRedraw();
  }
void MoveMouse(const int x,const int y)
  {
   if(g_zdrag){ZoneDragMove(x,y);return;}
   if(g_toolbar_drag){MoveToolbar(x,y);return;}
   if(g_drag==0)return;
   if(g_selected<0 || g_selected>=g_count){CancelDrag();return;}
   // Dead zone: pressing a handle or a line without moving it must never let the
   // OHLC magnet shift it (it would otherwise jump on a simple or double click).
   if(g_drag>=2 && MathAbs(x-g_drag_x)+MathAbs(y-g_drag_y)<4)
     {if(!SamePlacement(g_sets[g_selected],g_drag_backup)){g_sets[g_selected]=g_drag_backup;g_dirty=true;}return;}
   datetime t=0;double p=0;
   if(g_drag<=3)
     {
      if(!Snap(x,y,g_sets[g_selected].source_tf,t,p,InpSnapRadiusPixels))return;
      if(g_drag==2){g_sets[g_selected].ta=t;g_sets[g_selected].pa=p;}
      else {g_sets[g_selected].tb=t;g_sets[g_selected].pb=p;}
      if(g_drag==1)
        {
         g_sets[g_selected].left=(datetime)MathMin((long)g_sets[g_selected].ta,(long)t);
         g_sets[g_selected].right=(datetime)MathMax((long)g_sets[g_selected].ta,(long)t);
         if(g_sets[g_selected].right==g_sets[g_selected].left)g_sets[g_selected].right+=(datetime)PeriodSeconds(g_sets[g_selected].source_tf);
        }
     }
   else if(g_drag==7 || g_drag==8)
     {
      // Horizontal line: the line price snaps to the nearest OHLC; both anchors move by
      // the same amount, so the line can never tilt. The origin handle also moves in time.
      int line=LineLevel(g_drag_backup);
      if(line<0 || !Snap(x,y,g_sets[g_selected].source_tf,t,p,InpLineSnapPixels))return;
      double dp=p-FPLevelPrice(g_drag_backup.pa,g_drag_backup.pb,g_drag_backup.levels[line].value);
      g_sets[g_selected].pa=NormalizeDouble(g_drag_backup.pa+dp,_Digits);
      g_sets[g_selected].pb=NormalizeDouble(g_drag_backup.pb+dp,_Digits);
      if(g_drag==7)
        {
         long dt=(long)t-(long)g_drag_backup.left;
         g_sets[g_selected].ta=(datetime)((long)g_drag_backup.ta+dt);g_sets[g_selected].tb=(datetime)((long)g_drag_backup.tb+dt);
         g_sets[g_selected].left=(datetime)((long)g_drag_backup.left+dt);g_sets[g_selected].right=(datetime)((long)g_drag_backup.right+dt);
        }
     }
   else
     {
      if(!Point(x,y,t,p))return;
      if(g_drag==4 || g_drag==5)
        {
         // Deliberately do not write ta, tb, pa or pb in this branch.
         FPSetExtent(g_sets[g_selected].left,g_sets[g_selected].right,t,g_drag==4);
         if(g_drag==4)g_sets[g_selected].ray_left=false;else g_sets[g_selected].ray_right=false;
        }
      else if(g_drag==6)
        {
         long dt=(long)t-(long)g_drag_time;double dp=NormalizeDouble(p-g_drag_price,_Digits);
         g_sets[g_selected].ta=(datetime)((long)g_drag_backup.ta+dt);g_sets[g_selected].tb=(datetime)((long)g_drag_backup.tb+dt);
         g_sets[g_selected].pa=NormalizeDouble(g_drag_backup.pa+dp,_Digits);g_sets[g_selected].pb=NormalizeDouble(g_drag_backup.pb+dp,_Digits);
         g_sets[g_selected].left=(datetime)((long)g_drag_backup.left+dt);g_sets[g_selected].right=(datetime)((long)g_drag_backup.right+dt);
        }
     }
   g_dirty=true;
  }
// Price distance that hidden levels of a horizontal line span (about 80 px of the view).
double LineSpan()
  {
   double span=(g_view_max-g_view_min)*80.0/MathMax(1,g_height);
   if(!MathIsValidNumber(span) || span<=0)span=100*_Point;
   return NormalizeDouble(MathMax(span,10*_Point),_Digits);
  }
// Turns the drawing being created into a single-level horizontal line.
// clicked: single click -> origin snapped to OHLC, rayed to the right.
// otherwise: horizontal drag -> keeps the dragged extent.
bool MakeLine(FPSetup &s,const bool clicked)
  {
   datetime t=s.ta;double p=s.pa;
   if(clicked)
     {
      datetime st=0;double sp=0;
      if(Snap(g_drag_x,g_drag_y,(ENUM_TIMEFRAMES)_Period,st,sp,InpLineSnapPixels)){t=st;p=sp;}
     }
   int k=BoundaryLevel(s);
   if(k<0)return false;
   for(int i=0;i<s.count;i++)s.levels[i].enabled=(i==k);
   double delta=LineSpan(),v=s.levels[k].value;
   // Level price = pb + v*(pa-pb) is placed exactly on p for the 0% and 100% levels.
   if(v==0.0){s.pb=p;s.pa=NormalizeDouble(p+delta,_Digits);}
   else {s.pa=NormalizeDouble(p+(1.0-v)*delta,_Digits);s.pb=NormalizeDouble(s.pa-delta,_Digits);}
   if(s.pa==s.pb || !MathIsValidNumber(s.pa) || !MathIsValidNumber(s.pb))return false;
   if(clicked){s.left=t;s.right=t+(datetime)(10*PeriodSeconds());s.ray_right=true;}
   else s.ray_right=false;
   s.ta=s.left;s.tb=s.right;
   s.ray_left=false;s.diagonal=false;s.fill=false;s.hline=true;
   s.name="Line "+IntegerToString(s.uid);
   s.visible_mask|=(long)1<<g_tf;
   return true;
  }
void EndMouse(const int x,const int y)
  {
   if(g_zdrag){ZoneDragMove(x,y);ZoneDragEnd();return;}
   if(g_toolbar_drag)
     {MoveMouse(x,y);g_toolbar_drag=false;ReleaseScroll();if(g_toolbar_moved){g_ignore_toolbar_click_until=GetTickCount64()+180;SaveLayout();}g_toolbar_moved=false;return;}
   if(g_drag==0)return;
   if(g_selected<0 || g_selected>=g_count){CancelDrag();return;}
   MoveMouse(x,y);
   bool created=g_drag==1,line=false;
   if(created)
     {
      bool clicked=MathAbs(x-g_drag_x)+MathAbs(y-g_drag_y)<4;
      if(clicked || g_sets[g_selected].pa==g_sets[g_selected].pb)
        {
         if(!MakeLine(g_sets[g_selected],clicked)){CancelDrag();Status("Could not place a horizontal line here.");return;}
         line=true;
        }
     }
   else if(g_sets[g_selected].pa==g_sets[g_selected].pb)
     {CancelDrag();Status("Change canceled: anchors need two different prices.");return;}
   else if(SamePlacement(g_sets[g_selected],g_drag_backup))
     {g_drag=0;ReleaseScroll();g_dirty=true;return;} // A click on a handle: nothing to save.
   g_created=-1;g_drag=0;g_armed=false;ReleaseScroll();g_ui_dirty=true;g_dirty=true;
   if(!Save())
     {
      if(created){g_count--;g_selected=g_previous_selection;}
      else g_sets[g_selected]=g_drag_backup;
      g_dirty=true;return;
     }
   if(line)Status("Horizontal line placed. Drag its origin handle or the line to move it; double-click for properties.");
   else if(!created || RememberConfig(g_sets[g_selected]))Status("Drawings saved. Select a line; double-click a line for properties.");
  }
void RemoveAt(const int slot)
  {
   if(g_drag!=0)CancelDrag();
   if(slot<0 || slot>=g_count){Status("Select a drawing to delete.");return;}
   int previous=g_selected;FPSetup removed=g_sets[slot];
   CloseEditor();for(int i=slot;i<g_count-1;i++)g_sets[i]=g_sets[i+1];
   g_count--;
   g_selected=previous==slot?-1:(previous>slot?previous-1:previous);
   if(!Save())
     {for(int i=g_count;i>slot;i--)g_sets[i]=g_sets[i-1];g_sets[slot]=removed;g_count++;g_selected=previous;}
   else Status("Deleted "+removed.name+".");
   g_dirty=true;g_ui_dirty=true;
  }
void RemoveSelected(){RemoveAt(g_selected);}
void SelectNext(const int direction)
  {
   if(g_count==0){Status("No drawings yet. Click New Fib to draw one.");return;}
   CloseEditor();
   int pos=g_selected;
   for(int k=0;k<g_count;k++)
     {
      if(pos<0 || pos>=g_count)pos=direction>0?0:g_count-1;else pos=(pos+direction+g_count)%g_count;
      if(Visible(g_sets[pos])){g_selected=pos;g_ui_dirty=true;g_dirty=true;g_list_follow=true;Status("Selected "+g_sets[pos].name+".");return;}
     }
   Status("No drawing is visible on "+g_tf_names[g_tf]+".");
  }

// A chart/object click is a second release signal if the mouse-move release
// was lost (for example when releasing outside the chart and returning).
void FinishPointer(const int x,const int y)
  {
   g_prev_down=false;g_picker_drag=0;g_slider_drag=false;
   g_ui_defer_until=GetTickCount64()+32;
   if(g_drag!=0 && HitUI(x,y))CancelDrag();else EndMouse(x,y);
  }
// Chart scrolling is held while drawing/dragging, and while the pointer rests over the
// tool's own controls so slider, picker and panel drags never pan the chart. It is
// never released in the middle of a pressed drag.
void UpdateScrollHold(const int x,const int y,const bool down)
  {
   bool want=g_armed || g_drag!=0 || g_toolbar_drag || g_slider_drag || g_picker_drag!=0 || g_zdrag;
   if(!down && g_mouse_in && (HitUI(x,y) || ZoneDragHot(x,y)))want=true; // a strip ready to drag
   if(want)HoldScroll();else if(!down)ReleaseScroll();
  }
void HandlePointer(const int x,const int y,const bool down)
  {
   bool was_down=g_prev_down;
   g_mouse_x=x;g_mouse_y=y;g_mouse_in=(x>=0 && y>=0 && x<g_width && y<g_height);
   g_last_mouse=GetTickCount64();
   PickerMouse(x,y,down,was_down);
   SliderMouse(x,y,down,was_down);
   ListMouse(x,y,down,was_down);
   if(down && !was_down)BeginMouse(x,y);
   else if(down && (g_drag!=0 || g_toolbar_drag || g_zdrag))MoveMouse(x,y);
   else if(down)g_view_probe=true;
   else if(was_down || g_drag!=0 || g_toolbar_drag || g_zdrag)FinishPointer(x,y);
   if((down || was_down) && g_drag==0 && !g_toolbar_drag && !g_zdrag && !g_editor && g_popup==0 && !HitUI(x,y))
     {g_fast_view_until=GetTickCount64()+150;g_view_probe=true;}
   g_prev_down=down;
   UpdateScrollHold(x,y,down);
   g_hover_pending=true;
  }

// Remove this workspace's indicator; OnDeinit owns all chart-object cleanup.
// Saved drawings/presets are retained. Unapplied properties are not committed.
void DetachTool()
  {
   if(g_detaching)return;
   g_detaching=true;
   ResetLastError();
   if(!ChartIndicatorDelete(0,0,g_shortname))
     {
      int error=GetLastError();g_detaching=false;
      Status("Could not detach tool. Use Ctrl+I to remove Fibonacci Pro.");
      Print("Fibonacci Pro: detach failed, error ",error);
     }
  }
void Click(const string name)
  {
   if(StringFind(name,g_prefix)!=0)return;
   int type=RegType(name);
   if(type<0)return; // Canvases, tooltip and other non-control objects.
   if(StringFind(name,UIS("T."))==0 && GetTickCount64()<g_ignore_toolbar_click_until)return;
   if(type==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
   if(name==UIS("T.Close")){DetachTool();return;}
   // Explicit toolbar commands recover from a stale drawing/dragging state.
   if(StringFind(name,UIS("T."))==0 && type==OBJ_BUTTON && (g_drag!=0 || g_toolbar_drag || g_armed))CancelDrag();
   if(StringFind(name,Obj("R."))==0)
     {
      if(type!=OBJ_BUTTON)return;
      HarvestPresetName();
      if(name!=Obj("R.Delete"))g_delete_confirm="";
      if(name==Obj("R.Cancel")){ClosePopup();return;}
      if(name==Obj("R.Action")){PresetAction();return;}
      if(name==Obj("R.Delete")){PresetDelete();return;}
      if(name==Obj("R.Prev")){g_preset_page=(int)MathMax(0,g_preset_page-1);PresetBrowser(g_preset_save,false);return;}
      if(name==Obj("R.Next")){g_preset_page=(int)MathMin((int)MathMax(0,(g_preset_count-1)/7),g_preset_page+1);PresetBrowser(g_preset_save,false);return;}
      if(StringFind(name,Obj("R.Item"))==0)
        {int i=(int)StringToInteger(StringSubstr(name,StringLen(Obj("R.Item"))));if(i>=0 && i<g_preset_count){g_preset_name=g_preset_names[i];PresetBrowser(g_preset_save,false,false);}return;}
      return;
     }
   if(g_popup==4)return;
   if(StringFind(name,Obj("Q."))==0){if(type==OBJ_BUTTON)ZonePopupClick(name);return;}
   if(StringFind(name,Obj("D."))==0)
     {
      DropdownChoice((int)StringToInteger(StringSubstr(name,StringLen(Obj("D.")))));
      ClosePopup();g_ui_dirty=true;g_dirty=true;return;
     }
   if(StringFind(name,Obj("P.Color"))==0)
     {int i=(int)StringToInteger(StringSubstr(name,StringLen(Obj("P.Color"))));if(i>=0 && i<ArraySize(g_palette))PickApply(g_palette[i]);return;}
   if(name==Obj("P.Use")){PickApply(g_pick_color);return;}
   if(name==Obj("P.Cancel")){ClosePopup();return;}
   string key=StringSubstr(name,StringLen(UIS("")));
   if(key=="T.New"){Arm();return;}
   if(key=="T.Duplicate"){DuplicateSelected();return;}
   if(key=="T.Properties"){if(!g_editor)OpenEditor();return;}
   if(key=="T.Hide"){ToggleUI();return;}
   if(key=="T.Delete"){RemoveSelected();return;}
   if(key=="T.List"){ToggleList();return;}
   if(key=="T.Zones"){if(g_zeditor)CloseZones();else OpenZones();return;}
   if(StringFind(key,"Z.")==0){if(type==OBJ_BUTTON && g_zeditor)ZonesClick(StringSubstr(key,2));return;}
   if(StringFind(key,"L.")==0){if(type==OBJ_BUTTON && g_list)ListClick(key);return;}
   if(key=="T.Prev" || key=="T.Next"){SelectNext(key=="T.Next"?1:-1);return;}
   // Labels, edit boxes and the slider track are not commands.
   if(!g_editor || StringFind(key,"E.")!=0 || type!=OBJ_BUTTON)return;
   key=StringSubstr(key,2);
   if(key!="Cancel")
     {
      // Read active edits before their focus-loss events or an Apply click race.
      if(!HarvestEdits())return;
      if(g_ui_dirty){ClosePopup();BuildUI();}
     }
   if(key=="OK"){ApplyEditor(true);return;}if(key=="Apply"){ApplyEditor(false);return;}if(key=="Cancel"){CloseEditor();return;}
   if(key=="Save"){PresetBrowser(true);return;}if(key=="Load"){PresetBrowser(false);return;}
   if(StringFind(key,"Tab")==0){ClosePopup();g_tab=Lim((int)StringToInteger(StringSubstr(key,3)),0,4);g_ui_dirty=true;return;}
   if(StringFind(key,"Style")==0){Dropdown(1,(int)StringToInteger(StringSubstr(key,5)));return;}
   if(StringFind(key,"Width")==0){Dropdown(2,(int)StringToInteger(StringSubstr(key,5)));return;}
   if(key=="LblV"){Dropdown(5,-1);return;}if(key=="LblH"){Dropdown(6,-1);return;}if(key=="LblF"){Dropdown(7,-1);return;}
   if(StringFind(key,"Color")==0){Palette((int)StringToInteger(StringSubstr(key,5)));return;}
   if(key=="AllColor"){Palette(-5);return;}
   if(key=="FillTop"){Palette(-2);return;}if(key=="FillBottom"){Palette(-3);return;}if(key=="BaseColor"){Palette(-4);return;}
   if(StringFind(key,"On")==0 && key!="OnlySource")
     {int i=(int)StringToInteger(StringSubstr(key,2));if(i>=0 && i<g_edit.count)g_edit.levels[i].enabled=!g_edit.levels[i].enabled;}
   else if(StringFind(key,"Remove")==0)
     {int i=(int)StringToInteger(StringSubstr(key,6));if(i>=0 && i<g_edit.count){for(int k=i;k<g_edit.count-1;k++)g_edit.levels[k]=g_edit.levels[k+1];g_edit.count--;g_page=Lim(g_page,0,(int)MathMax(0,(g_edit.count-1)/g_rows));}}
   else if(key=="Add")
     {if(g_edit.count<FP_MAX_LEVELS){int i=g_edit.count++;DefaultLevel(g_edit.levels[i],.75);g_page=i/g_rows;}}
   else if(key=="Defaults"){Defaults(g_edit);g_page=0;}
   else if(key=="PageBack")g_page=(int)MathMax(0,g_page-1);
   else if(key=="PageNext")g_page=(int)MathMin((int)MathMax(0,(g_edit.count-1)/g_rows),g_page+1);
   else if(key=="Labels")g_edit.labels=!g_edit.labels;
   else if(key=="Diagonal")g_edit.diagonal=!g_edit.diagonal;
   else if(key=="Lock")g_edit.anchors_locked=!g_edit.anchors_locked;
   else if(key=="LineMode")g_edit.hline=!g_edit.hline;
   else if(key=="RayL")g_edit.ray_left=!g_edit.ray_left;
   else if(key=="RayR")g_edit.ray_right=!g_edit.ray_right;
   else if(key=="Fill")g_edit.fill=!g_edit.fill;
   else if(key=="Gradient")g_edit.gradient=!g_edit.gradient;
   else if(key=="FillRays")g_edit.fill_rays=!g_edit.fill_rays;
   else if(key=="AllLower"){g_edit.visible_mask=Allowed(g_edit.source_tf);g_edit.visibility_mode=1;}
   else if(key=="OnlySource"){g_edit.visible_mask=(long)1<<TFIndex(g_edit.source_tf);g_edit.visibility_mode=2;}
   else if(key=="AllTF"){g_edit.visible_mask=FP_ALL_TF_MASK;g_edit.visibility_mode=0;}
   else if(StringFind(key,"TF")==0)
     {
      // Every timeframe can be toggled, including those above the drawing timeframe.
      int i=(int)StringToInteger(StringSubstr(key,2));
      if(StringLen(key)>2 && i>=0 && i<FP_TF_COUNT){g_edit.visible_mask^=((long)1<<i);g_edit.visibility_mode=0;}
     }
   else return; // Unknown command: keep the panel (and any edit focus) as it is.
   g_ui_dirty=true;g_dirty=true;
  }
void EndEdit(const string name)
  {
   if(!g_editor || StringFind(name,UIS("E."))!=0 || RegType(name)!=OBJ_EDIT)return;
   string key=StringSubstr(name,StringLen(UIS("E."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   bool accepted=true;
   if(key=="Name")g_edit.name=StringSubstr(text,0,120);
   else if(key=="Description")g_edit.description=StringSubstr(text,0,240);
   else if(StringFind(key,"Text")==0)
     {int i=(int)StringToInteger(StringSubstr(key,4));if(i>=0 && i<g_edit.count)g_edit.levels[i].description=StringSubstr(text,0,160);}
   else if(StringFind(key,"Value")==0)
     {int i=(int)StringToInteger(StringSubstr(key,5));double v=StringToDouble(text);if(i>=0 && i<g_edit.count && Numeric(text) && MathIsValidNumber(v) && MathAbs(v)<=1000)g_edit.levels[i].value=v;else accepted=false;}
   else if(key=="Opacity")
     {if(Numeric(text)){g_edit.opacity=Lim((int)StringToInteger(text),0,100);PlaceOpacityThumb();}else accepted=false;}
   else if(key=="PriceA" || key=="PriceB")
     {
      double p=NormalizeDouble(StringToDouble(text),_Digits);
      if(Numeric(text) && MathIsValidNumber(p) && p!=(key=="PriceA"?g_edit.pb:g_edit.pa))
        {if(key=="PriceA")g_edit.pa=p;else g_edit.pb=p;}
      else accepted=false;
     }
   else if(key=="TimeA" || key=="TimeB" || key=="Left" || key=="Right")
     {
      datetime t=StringToTime(text);
      if(t<=0)accepted=false;
      else if(key=="TimeA")g_edit.ta=t;else if(key=="TimeB")g_edit.tb=t;
      else if(key=="Left"){if(t<g_edit.right)g_edit.left=t;else accepted=false;}
      else if(key=="Right"){if(t>g_edit.left)g_edit.right=t;else accepted=false;}
     }
   else return;
   if(!accepted){g_edit_error=true;Status("Invalid value; previous setting restored.");g_ui_dirty=true;}
   // Valid text edits do not destroy/recreate all controls on focus loss.
   g_dirty=true;
  }
bool HarvestEdits()
  {
   if(!g_editor)return true;
   g_edit_error=false;
   // Only this panel's edit boxes, known from the registry: no scan of every chart object.
   string prefix=UIS("E.");
   for(int i=0;i<g_reg_count;i++)
      if(g_reg[i].type==OBJ_EDIT && StringFind(g_reg[i].name,prefix)==0)EndEdit(g_reg[i].name);
   return !g_edit_error;
  }

// ------------------------------------------------------------ instance ownership
// MT5 can run a new copy's OnInit before the old copy's OnDeinit (timeframe switch),
// and a saved profile can restore the old marker object. Instead of failing, a new copy
// waits until the workspace marker is gone or stale and the storage lock is free.
bool MarkerIsLive(const ulong now)
  {
   if(ObjectFind(0,g_alive)<0)return false;
   string parts[];
   if(StringSplit(ObjectGetString(0,g_alive,OBJPROP_TOOLTIP),'|',parts)!=2 || parts[0]==g_token)return false;
   long stamp=StringToInteger(parts[1]);
   return stamp>0 && (ulong)stamp<=now && now-(ulong)stamp<FP_STALE_MS;
  }
bool MarkerIsMine()
  {
   if(ObjectFind(0,g_alive)<0)return false;
   string parts[];
   return StringSplit(ObjectGetString(0,g_alive,OBJPROP_TOOLTIP),'|',parts)==2 && parts[0]==g_token;
  }
void Heartbeat(const ulong now)
  {g_last_beat=now;ObjectSetString(0,g_alive,OBJPROP_TOOLTIP,g_token+"|"+IntegerToString((long)now));}
bool CreateMarker(const ulong now)
  {
   if(!ObjectCreate(0,g_alive,OBJ_LABEL,0,0,0))return false;
   ObjectSetInteger(0,g_alive,OBJPROP_HIDDEN,true);ObjectSetInteger(0,g_alive,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,g_alive,OBJPROP_COLOR,clrNONE);ObjectSetString(0,g_alive,OBJPROP_TEXT,"");
   Heartbeat(now);
   return true;
  }
void LoadState()
  {
   bool exists=FileIsExist(g_store);
   g_primary_valid=LoadFile(g_store);
   if(!g_primary_valid && exists)
     {
      if(LoadFile(g_store+".bak"))g_status="Recovered the previous snapshot from backup.";
      else g_status="Saved snapshot unreadable. Files retained; check Experts log.";
      Print("Fibonacci Pro: ",g_status," Snapshot: ",g_store);
     }
   g_has_last_config=ReadPreset(g_last_store,g_last_config);
   if(!g_has_last_config)g_has_last_config=ReadPreset(g_last_store+".bak",g_last_config);
   g_last_config_persisted=g_has_last_config;
   if(!g_has_last_config && g_count>0){g_last_config=g_sets[g_count-1];g_has_last_config=true;}
   g_layout_store=g_store+".ui";LoadLayout();
   LoadZones();
  }
// 0 acquired, 1 another live copy owns the workspace, 2 storage lock busy, 3 error.
int TryAcquire()
  {
   if(g_owner)return 0;
   ulong now=GetTickCount64();
   if(MarkerIsLive(now))return 1;
   if(g_file_lock==INVALID_HANDLE)g_file_lock=FileOpen(g_store+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_file_lock==INVALID_HANDLE)return 2;
   // Leftovers from a crashed copy or from a chart restored out of a saved profile.
   ObjectsDeleteAll(0,g_ws_prefix);
   if(!CreateMarker(now)){FileClose(g_file_lock);g_file_lock=INVALID_HANDLE;return 3;}
   g_owner=true;
   LoadState();
   g_old_mouse=(bool)ChartGetInteger(0,CHART_EVENT_MOUSE_MOVE);ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   g_old_wheel=(bool)ChartGetInteger(0,CHART_EVENT_MOUSE_WHEEL);ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,true);
   IndicatorSetString(INDICATOR_SHORTNAME,g_shortname);
   g_chart_fg=(color)ChartGetInteger(0,CHART_COLOR_FOREGROUND);g_chart_bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   g_width=0;g_height=0;ViewChanged();g_ui_dirty=true;g_dirty=true;g_view_probe=true;
   Status("Panel: "+InpPanelHotkey+" | Duplicate: "+InpDuplicateHotkey+" | "+IntegerToString(g_count)+" drawing(s) loaded.");
   return 0;
  }
void WaitForOwnership(const ulong now)
  {
   if(now-g_wait_last<50)return;
   g_wait_last=now;
   int state=TryAcquire();
   if(state==0)return;
   if(state==1 && now-g_wait_since>FP_DUPLICATE_MS && !g_dup_reported)
     {
      g_dup_reported=true;
      Print("Fibonacci Pro: workspace \"",InpWorkspace,"\" is already active on this chart. Use a different InpWorkspace; this copy is removed.");
      ChartIndicatorDelete(0,0,g_pending_name);
     }
   if(state>=2 && now-g_wait_since>FP_DUPLICATE_MS*2 && !g_wait_reported)
     {
      g_wait_reported=true;
      Print("Fibonacci Pro: waiting for snapshot ",g_store," to be released by another chart or copy. Choose a unique InpStorageKey if this persists.");
     }
  }
// Once a second: recover from objects deleted by other programs and from mouse-move
// events being switched off (both made the tool appear frozen).
void Housekeeping(const ulong now)
  {
   if(now-g_last_house<1000)return;
   g_last_house=now;
   if(!(bool)ChartGetInteger(0,CHART_EVENT_MOUSE_MOVE))ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   if(ObjectFind(0,g_alive)<0)CreateMarker(now);
   if(g_canvas_ready && ObjectFind(0,Obj("Lines"))<0)
     {g_fill_canvas.Destroy();g_line_canvas.Destroy();g_canvas_ready=false;g_dirty=true;}
   if(!g_hidden && RegFind(UIS("T.New"))>=0 && ObjectFind(0,UIS("T.New"))<0)
     {RegDeletePrefix(UIS(""));g_status_shown=false;g_ui_dirty=true;}
  }

int OnInit()
  {
   if(!ParseHotkey(InpPanelHotkey,g_panel_key,g_panel_ctrl,g_panel_shift,g_panel_alt) || !ParseHotkey(InpDuplicateHotkey,g_duplicate_key,g_duplicate_ctrl,g_duplicate_shift,g_duplicate_alt)
      || !ParseHotkey(InpZonesHotkey,g_zones_key,g_zones_ctrl,g_zones_shift,g_zones_alt) || ShortcutsClash())
     {Print("Fibonacci Pro: use three different shortcuts, e.g. Ctrl+Shift+H, Ctrl+Shift+D and Ctrl+Shift+K (letters, digits or F1..F12).");return INIT_PARAMETERS_INCORRECT;}
   g_tf=TFIndex((ENUM_TIMEFRAMES)_Period);
   if(g_tf<0){Print("Fibonacci Pro: unsupported chart timeframe.");return INIT_FAILED;}
   g_frame_ms=Lim(InpFrameMilliseconds,8,100);
   g_ws_prefix="FP5."+WorkspaceTag()+".";
   g_token=MakeToken();
   g_prefix=g_ws_prefix+g_token+".";
   g_alive=g_ws_prefix+"Alive";
   string key=StringLen(InpStorageKey)>0?SafeName(InpStorageKey):IntegerToString(ChartID());
   FolderCreate("FibonacciPro");
   FolderCreate("FibonacciPro\\Presets");
   g_last_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".last.fpp";
   g_zstore="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".zones";
   g_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(_Symbol)+"_"+SafeName(InpWorkspace)+"_"+key+".bin";
   g_shortname="Fibonacci Pro ["+InpWorkspace+"]";
   g_pending_name=g_shortname+" ~"+g_token;
   IndicatorSetString(INDICATOR_SHORTNAME,g_pending_name);
   if(!EventSetMillisecondTimer(g_frame_ms))return INIT_FAILED;
   g_wait_since=GetTickCount64();g_wait_last=0;
   TryAcquire(); // Otherwise retried from the timer until the previous copy has unloaded.
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   // A copy that never acquired the workspace owns no objects, files or chart settings.
   if(!g_owner)return;
   if(g_drag!=0 || g_toolbar_drag)CancelDrag();
   ReleaseScroll();
   // Last committed state only; unapplied dialog edits are deliberately discarded.
   ClosePopup();g_fill_canvas.Destroy();g_line_canvas.Destroy();DestroyTip();
   // Instance-unique prefix: never deletes objects of a newer copy of this workspace.
   ObjectsDeleteAll(0,g_prefix);
   bool mine=MarkerIsMine();
   if(mine)ObjectDelete(0,g_alive);
   if(g_file_lock!=INVALID_HANDLE){FileClose(g_file_lock);g_file_lock=INVALID_HANDLE;}
   g_owner=false;
   bool other_instance=!mine;
   for(int i=ObjectsTotal(0)-1;i>=0 && !other_instance;i--)
     {string n=ObjectName(0,i);if(n!=g_alive && StringFind(n,"FP5.")==0 && StringFind(n,".Alive")>=0)other_instance=true;}
   if(!g_old_mouse && !other_instance)ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);
   if(!g_old_wheel && !other_instance)ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,false);
   ChartRedraw();
  }
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(!g_owner)return rates_total;
   g_view_probe=true;if(rates_total!=prev_calculated)g_dirty=true;
   return rates_total;
  }
// Shared by mouse/chart events and the timer: no extra timer wait after an event.
void RefreshFrame(const bool probe=false)
  {
   if(g_detaching)return;
   ulong now=GetTickCount64();
   if(!g_owner){WaitForOwnership(now);return;}
   if(probe)g_view_probe=true;
   // Coalesce high-frequency events; leave dirty/probe flags set for the next frame.
   if(now-g_last_frame<(ulong)g_frame_ms)return;
   g_last_frame=now;
   if(now-g_last_beat>=FP_BEAT_MS)Heartbeat(now);
   Housekeeping(now);
   ZoneTick(now);
   // MT5 can deliver a mouse event before its chart projection has updated.
   // Poll each frame during chart panning and for 150 ms after the last pan event.
   if(g_view_probe || now<g_fast_view_until || now-g_last_view>=200)
     {if(ViewChanged())g_dirty=true;g_last_view=now;g_view_probe=false;}
   bool changed=false;
   if(g_dirty && now>=g_render_retry_after){Render();changed=true;}
   // Leave a short grace period for queued native OBJECT_CLICK events.
   if(g_ui_dirty && !g_prev_down && !g_toolbar_drag && g_drag==0 && !g_slider_drag && !g_zdrag && now>=g_ui_defer_until)
     {ClosePopup();BuildUI();changed=true;}
   else if(g_status_dirty || (g_status_shown && now>=g_status_until))
     {UpdateStatusObjects(now);changed=true;}
   if(g_hover_pending){if(UpdateHover())changed=true;}
   else if(g_tip_visible && now-g_last_mouse>FP_TIP_IDLE_MS){if(HideTip())changed=true;}
   if(changed || g_need_redraw){g_need_redraw=false;ChartRedraw();}
  }
void OnTimer(){RefreshFrame();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(g_detaching || !g_owner)return;
   if(id==CHARTEVENT_CHART_CHANGE){g_fast_view_until=GetTickCount64()+150;RefreshFrame(true);return;}
   if(id==CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(sparam==Obj("R.Name"))HarvestPresetName();
      else if(sparam==UIS("L.Search")){g_list_search=ObjectGetString(0,sparam,OBJPROP_TEXT);g_list_page=0;g_ui_dirty=true;}
      else if(g_popup==0){EndEdit(sparam);ZEndEdit(sparam);}
      return;
     }
   if(id==CHARTEVENT_MOUSE_WHEEL){ListWheel((int)(short)lparam,(int)(short)(lparam>>16),(int)dparam);RefreshFrame();return;}
   if(id==CHARTEVENT_CLICK)
     {if(g_prev_down || g_drag!=0 || g_toolbar_drag || g_zdrag)FinishPointer((int)lparam,(int)dparam);return;}
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(g_prev_down || g_drag!=0 || g_toolbar_drag || g_zdrag)FinishPointer((int)lparam,(int)dparam);
      if(StringFind(sparam,g_prefix)==0)Click(sparam);
      else if(StringFind(sparam,"FP5.")!=0 && !g_editor && g_drag==0 && g_selected>=0){g_selected=-1;g_dirty=true;g_ui_dirty=true;}
      RefreshFrame();
      return;
     }
   if(id==CHARTEVENT_KEYUP)
     {if((int)lparam==g_panel_key)g_panel_key_held=false;if((int)lparam==g_duplicate_key)g_duplicate_key_held=false;if((int)lparam==g_zones_key)g_zones_key_held=false;return;}
   if(id==CHARTEVENT_KEYDOWN)
     {
      int key=(int)lparam;
      if(key==27){if(g_zdrag)CancelDrag();else if(g_popup!=0)ClosePopup();else if(g_editor)CloseEditor();else if(g_zeditor)CloseZones();else if(g_list){g_list=false;g_ui_dirty=true;}else CancelDrag();HideTip();return;}
      bool ctrl=(TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL)&0x8000)!=0;
      bool shift=(TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT)&0x8000)!=0;
      bool alt=(TerminalInfoInteger(TERMINAL_KEYSTATE_MENU)&0x8000)!=0;
      // Bare-letter shortcuts must not fire while the user types properties.
      if((g_editor || g_zeditor || g_list) && !ctrl && !alt)return;
      if(FPShortcutMatch(key,g_panel_key,ctrl,shift,alt,g_panel_ctrl,g_panel_shift,g_panel_alt))
        {if(!g_panel_key_held){g_panel_key_held=true;ToggleUI();}return;}
      if(FPShortcutMatch(key,g_zones_key,ctrl,shift,alt,g_zones_ctrl,g_zones_shift,g_zones_alt))
        {if(!g_zones_key_held){g_zones_key_held=true;ToggleZonesShown();}return;}
      if(g_popup!=0)return;
      if(FPShortcutMatch(key,g_duplicate_key,ctrl,shift,alt,g_duplicate_ctrl,g_duplicate_shift,g_duplicate_alt))
        {if(!g_duplicate_key_held){g_duplicate_key_held=true;DuplicateSelected();}return;}
     }
   if(id==CHARTEVENT_MOUSE_MOVE)
     {
      int x=(int)lparam,y=(int)dparam;bool down=(((int)StringToInteger(sparam)&1)!=0);
      HandlePointer(x,y,down);
      RefreshFrame();
     }
  }
