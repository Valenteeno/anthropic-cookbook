// Fibonacci Pro 1.60 -- custom drawing indicator for MetaTrader 5.
// No trading functions, DLLs, network access or external fonts/assets.
// Install in MQL5/Indicators, compile with the current MetaEditor 5.
#property copyright "Custom implementation for the user"
#property version   "1.60"
#property description "Independent Fibonacci anchors, horizontal lines, per-level styling, alpha fill and hover info."
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
input int    InpFrameMilliseconds=16;  // Requested redraw interval (16..100 ms)
input double InpUIScale=1.0;           // Panel scaling (0.75..2.0)
input color  InpDefaultColor=clrDarkOrange;
input int    InpMaximumSetups=64;      // 1..128 drawings per workspace
input bool   InpHoverCandleInfo=true;  // Hover a candle to show its OHLC
input bool   InpHoverFibInfo=true;     // Hover a Fib level to show its details
input string InpPanelHotkey="Ctrl+Shift+H";     // Hide/show the full tool interface
input string InpDuplicateHotkey="Ctrl+Shift+D"; // Duplicate highlighted custom Fib

#define FP_TOOLBAR_WIDTH 418
#define FP_TOOLBAR_HEIGHT 49
#define FP_PANEL_WIDTH 488
#define FP_MAX_SETUPS 128
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
int g_picker_target=-1; // >=0 level; -2 top fill; -3 bottom fill; -4 base/diagonal
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
   g_primary_valid=true;
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
  {RegDeletePrefix(Obj("P."));RegDeletePrefix(Obj("D."));RegDeletePrefix(Obj("R."));if(g_picker_ready){g_picker.Destroy();g_picker_ready=false;}g_popup=0;g_picker_drag=0;}
void CloseEditor()
  {ClosePopup();g_editor=false;g_slider_drag=false;g_ui_dirty=true;g_dirty=true;}
void OpenEditor()
  {
   if(g_selected<0 || g_selected>=g_count){Status("Select a Fibonacci drawing first.");return;}
   if(g_drag!=0 || g_armed)return;
   ClosePopup();g_edit=g_sets[g_selected];g_editor=true;g_page=0;g_ui_dirty=true;g_dirty=true;
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
   Label("T.Grip",":: Fibonacci Pro   (drag to move)",x+U(7),y+U(3),g_chart_fg);
   string title=g_selected>=0 && g_selected<g_count?g_sets[g_selected].name:"No selection";
   Tooltip("T.Grip",title+" | "+g_status+" | Drag title to move");
   Button("T.Close","×",x+U(FP_TOOLBAR_WIDTH-28),y+U(1),20,18);
   Tooltip("T.Close","Detach Fibonacci Pro from this chart (saved drawings retained)");
   x+=U(8);y+=U(23);
   Button("T.New",g_armed?"Draw now...":"New Fib",x,y,78,22,g_armed?clrLightSteelBlue:clrWhite);
   Tooltip("T.New","Then press-drag-release for a Fib with the last used levels, or single-click for a horizontal line snapped to OHLC");
   x+=U(80);
   Button("T.Prev","<",x,y,23);x+=U(25);
   Button("T.Next",">",x,y,23);x+=U(25);
   Button("T.Properties","Properties",x,y,82);x+=U(84);
   Button("T.Duplicate","Duplicate",x,y,72);x+=U(74);
   Button("T.Delete","Delete",x,y,52);x+=U(54);
   Button("T.Hide","Hide UI",x,y,60);
  }
void PlaceOpacityThumb()
  {
   if(!g_slider_on)return;
   int tx=g_slider_x0+(int)MathRound((g_slider_x1-g_slider_x0)*g_edit.opacity/100.0)-U(5);
   Box("E.OpThumb",tx,g_slider_y0+U(3),10,20,clrDimGray);
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
   if(!g_hidden){BuildToolbar();if(g_editor)BuildEditor();}
   UpdateStatusObjects(GetTickCount64());
   RegSweep(UIS(""));
  }

void RefreshPresetList()
  {
   g_preset_count=0;string filename;
   long search=FileFindFirst("FibonacciPro\\Presets\\*.fpp",filename);
   if(search!=INVALID_HANDLE)
     {
      do
        {int n=StringLen(filename);if(n>4 && g_preset_count<256 && StringSubstr(filename,n-4)==".fpp")g_preset_names[g_preset_count++]=StringSubstr(filename,0,n-4);}
      while(FileFindNext(search,filename));
      FileFindClose(search);
     }
   for(int i=0;i<g_preset_count-1;i++)for(int j=i+1;j<g_preset_count;j++)
     if(StringCompare(g_preset_names[i],g_preset_names[j])>0){string temp=g_preset_names[i];g_preset_names[i]=g_preset_names[j];g_preset_names[j]=temp;}
  }
void PresetMessage(const string text)
  {SetText(Obj("R.Message"),StringSubstr(text,0,52));ChartRedraw();}
void HarvestPresetName()
  {if(RegFind(Obj("R.Name"))>=0)g_preset_name=ObjectGetString(0,Obj("R.Name"),OBJPROP_TEXT);}
void PresetBrowser(const bool save_mode,const bool reset_page=true,const bool harvest=true)
  {
   if(!g_editor)return;
   if(g_popup==4 && harvest)HarvestPresetName();
   ClosePopup();g_popup=4;g_preset_save=save_mode;
   if(reset_page){RefreshPresetList();g_preset_page=0;}
   g_preset_page=Lim(g_preset_page,0,(int)MathMax(0,(g_preset_count-1)/7));
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(20);
   if(g_popup_y+U(326)>g_height)g_popup_y=(int)MathMax(4,g_height-U(326)-4);
   int px=g_popup_x,py=g_popup_y;
   UIBase(Obj("R.Background"),OBJ_RECTANGLE_LABEL,px,py,U(360),U(326),"",clrWhiteSmoke,clrBlack,390);
   UIBase(Obj("R.Title"),OBJ_LABEL,px+U(10),py+U(8),0,0,save_mode?"Save configuration preset":"Load or delete a configuration preset",clrWhite,clrBlack,400);
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
   UIBase(Obj("R.Message"),OBJ_LABEL,px+U(10),py+U(267),0,0,save_mode?"Choose a name; saving replaces that named preset.":"Choose a preset; anchors stay unchanged.",clrWhite,clrBlack,400);
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
   if(!g_editor || g_popup!=4)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Use a short name without path or special characters.");return;}
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
   if(!g_editor || g_popup!=4 || g_preset_save)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Select a preset to delete.");return;}
   string filename="FibonacciPro\\Presets\\"+g_preset_name+".fpp";
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
   if(!g_editor)return;
   if((kind==1 || kind==2) && (row<0 || row>=g_edit.count))return;
   string source=kind==1?UIS("E.Style"+IntegerToString(row)):(kind==2?UIS("E.Width"+IntegerToString(row)):(kind==5?UIS("E.LblV"):(kind==6?UIS("E.LblH"):UIS("E.LblF"))));
   int ri=RegFind(source);if(ri<0)return;
   int sx=g_reg[ri].x,sy=g_reg[ri].y,sh=g_reg[ri].h;
   ClosePopup();g_popup=kind;g_popup_row=row;
   string items[];int current=0,w=110;
   if(kind==1){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=g_style_names[i];current=g_edit.levels[row].style;}
   else if(kind==2){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=IntegerToString(i+1);current=g_edit.levels[row].width-1;w=48;}
   else if(kind==5){ArrayResize(items,2);items[0]=LabelVText(0);items[1]=LabelVText(1);current=g_edit.label_v;w=120;}
   else if(kind==6){ArrayResize(items,2);items[0]=LabelHText(0);items[1]=LabelHText(1);current=g_edit.label_h;w=130;}
   else {ArrayResize(items,2);items[0]="Fixed at fib end";items[1]="Float at chart edge (rays)";current=g_edit.label_float?1:0;w=180;}
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
   if(!g_editor || choice<0 || choice>=g_popup_items)return;
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
   if(g_picker_target>=0 && g_picker_target<g_edit.count)g_edit.levels[g_picker_target].ink=ink;
   else if(g_picker_target==-2)g_edit.fill_top=ink;
   else if(g_picker_target==-3)g_edit.fill_bottom=ink;
   else if(g_picker_target==-4)g_edit.base_color=ink;
   ClosePopup();g_dirty=true;g_ui_dirty=true;
  }
void Palette(const int target)
  {
   if(!g_editor || target>=g_edit.count || target<-4 || target==-1)return;
   ClosePopup();g_popup=3;g_picker_target=target;
   g_pick_color=target>=0?g_edit.levels[target].ink:(target==-2?g_edit.fill_top:(target==-3?g_edit.fill_bottom:g_edit.base_color));RGBtoHSV(g_pick_color);
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(28);
   if(g_popup_y+U(365)>g_height)g_popup_y=(int)MathMax(4,g_height-U(365)-4);
   UIBase(Obj("P.BG"),OBJ_RECTANGLE_LABEL,g_popup_x,g_popup_y,U(360),U(354),"",clrWhiteSmoke,clrBlack,350);
   UIBase(Obj("P.Title"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(7),0,0,"All MT5 named colors + visual spectrum",clrWhite,clrBlack,360);
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
   if(!g_editor || g_hidden || g_tab!=4 || !g_slider_on || g_popup!=0){g_slider_drag=false;return;}
   if(down && !was_down && x>=g_slider_x0-U(6) && x<=g_slider_x1+U(6) && y>=g_slider_y0 && y<=g_slider_y1)g_slider_drag=true;
   if(!down){g_slider_drag=false;return;}
   if(!g_slider_drag)return;
   int value=Lim((int)MathRound(100.0*(x-g_slider_x0)/MathMax(1,g_slider_x1-g_slider_x0)),0,100);
   if(value==g_edit.opacity)return;
   g_edit.opacity=value;
   SetText(UIS("E.Opacity"),IntegerToString(value));
   PlaceOpacityThumb();
   g_dirty=true;
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
void HLine(const int x0,const int x1,const int y,const color ink,const int width,const int style)
  {
   if(y<0 || y>=g_height || x1<0 || x0>=g_width)return;
   int l=Lim(x0,0,g_width-1),r=Lim(x1,0,g_width-1),top=Lim(y-(width-1)/2,0,g_height-1),bottom=Lim(top+width-1,0,g_height-1);
   if(l>r)return;
   uint argb=ColorToARGB(ink);
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
   hash=FPMix(hash,s.gradient?1:0);hash=FPMix(hash,s.opacity);
   return hash;
  }
void DrawFill(FPSetup &s,const int slot)
  {
   int x0=0,y0=0,x1=0,y1=0,top=0,bottom=0;
   if(!FillRect(s,slot,x0,y0,x1,y1,top,bottom))return;
   uchar alpha=(uchar)MathRound(s.opacity*255.0/100.0);
   if(!s.gradient)g_fill_canvas.FillRectangle(x0,y0,x1,y1,ColorToARGB(s.fill_top,alpha));
   else for(int y=y0;y<=y1;y++)g_fill_canvas.FillRectangle(x0,y,x1,y,ColorToARGB(FPBlend(s.fill_top,s.fill_bottom,(double)(y-top)/MathMax(1,bottom-top)),alpha));
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
   bool sel=g_selected>=0 && g_selected<g_count;
   // The fill layer is re-uploaded only when its pixels would actually change
   // (each upload copies a full chart-sized bitmap to the terminal).
   ulong sig=FPMix(FPMix(FPMix((ulong)1469598103934665603,g_width),g_height),sel?g_selected:-1);
   for(int i=0;i<g_count;i++)
     {if(sel && g_editor && i==g_selected)sig=FillSignatureOf(g_edit,i,sig);else sig=FillSignatureOf(g_sets[i],i,sig);}
   if(sig!=g_fill_sig)
     {
      g_fill_canvas.Erase(0);
      for(int i=0;i<g_count;i++)if(i!=g_selected)DrawFill(g_sets[i],i);
      if(sel){if(g_editor)DrawFill(g_edit,g_selected);else DrawFill(g_sets[g_selected],g_selected);}
      g_fill_canvas.Update(false);g_fill_sig=sig;
     }
   g_line_canvas.Erase(0);
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
      if(g_width>30)g_scale=MathMin(g_scale,MathMax(.75,(g_width-24)/500.0));
      g_rows=Lim((int)((g_height-U(280))/U(24)),6,10);g_panel_x=U(12);g_panel_y=U(94);
      g_toolbar_x=Lim(U(g_toolbar_lx),0,(int)MathMax(0,g_width-U(FP_TOOLBAR_WIDTH)));
      g_toolbar_y=Lim(U(g_toolbar_ly),0,(int)MathMax(0,g_height-U(FP_TOOLBAR_HEIGHT)));
      g_ui_dirty=true;
      if(g_editor){ClosePopup();g_ui_dirty=true;}
     }
   g_view_first=first;g_view_time=first_time;g_view_scale=scale;g_view_bars=bars;g_view_min=lo;g_view_max=hi;
   return changed;
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
   ArrayResize(lines,6);
   lines[0]=TimeToString(iTime(_Symbol,PERIOD_CURRENT,shift),TIME_DATE|TIME_MINUTES)+"   "+_Symbol+" "+g_tf_names[g_tf];
   lines[1]="Open\t"+DoubleToString(o,_Digits);
   lines[2]="High\t"+DoubleToString(h,_Digits);
   lines[3]="Low\t"+DoubleToString(l,_Digits);
   lines[4]="Close\t"+DoubleToString(c,_Digits);
   lines[5]="Range\t"+DoubleToString((h-l)/_Point,0)+" pts";
   accent=c>=o?clrSeaGreen:clrCrimson;
  }
bool UpdateHover()
  {
   g_hover_pending=false;
   int x=g_mouse_x,y=g_mouse_y;
   bool allowed=(InpHoverCandleInfo || InpHoverFibInfo) && g_mouse_in && !g_prev_down && g_drag==0 && !g_toolbar_drag
                && !g_slider_drag && g_picker_drag==0 && g_popup==0 && !HitUI(x,y);
   if(!allowed)return HideTip();
   string lines[];color accent=clrNONE;int slot=-1,level=-1,shift=-1;
   if(InpHoverFibInfo && FindFibAt(x,y,slot,level))
     {if(g_editor && slot==g_selected)FibTip(g_edit,level,lines,accent);else FibTip(g_sets[slot],level,lines,accent);}
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
   if(g_toolbar_drag){g_toolbar_drag=false;g_toolbar_moved=false;SaveLayout();}
   if(g_created>=0 && g_created<g_count){g_count--;g_selected=g_previous_selection;}
   else if(g_drag!=0 && g_selected>=0 && g_selected<g_count)g_sets[g_selected]=g_drag_backup;
   g_created=-1;g_drag=0;g_armed=false;g_slider_drag=false;ReleaseScroll();g_dirty=true;g_ui_dirty=true;
  }
bool HitCloseButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-28) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-8) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
void BeginMouse(const int x,const int y)
  {
   g_panel_key_held=false;g_duplicate_key_held=false;
   if(!HitCloseButton(x,y) && !g_hidden && !g_armed && g_drag==0 && g_popup==0 && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH) && y>=g_toolbar_y && y<g_toolbar_y+U(21))
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
   if(hit!=g_selected){g_dirty=true;g_ui_dirty=true;}
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
void RemoveSelected()
  {
   if(g_drag!=0)CancelDrag();
   if(g_selected<0 || g_selected>=g_count){Status("Select a drawing to delete.");return;}
   int selected=g_selected;FPSetup removed=g_sets[selected];
   CloseEditor();for(int i=selected;i<g_count-1;i++)g_sets[i]=g_sets[i+1];
   g_count--;g_selected=-1;
   if(!Save())
     {for(int i=g_count;i>selected;i--)g_sets[i]=g_sets[i-1];g_sets[selected]=removed;g_count++;g_selected=selected;}
   else Status("Deleted "+removed.name+".");
   g_dirty=true;g_ui_dirty=true;
  }
void SelectNext(const int direction)
  {
   if(g_count==0){Status("No drawings yet. Click New Fib to draw one.");return;}
   CloseEditor();
   int pos=g_selected;
   for(int k=0;k<g_count;k++)
     {
      if(pos<0 || pos>=g_count)pos=direction>0?0:g_count-1;else pos=(pos+direction+g_count)%g_count;
      if(Visible(g_sets[pos])){g_selected=pos;g_ui_dirty=true;g_dirty=true;Status("Selected "+g_sets[pos].name+".");return;}
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
   bool want=g_armed || g_drag!=0 || g_toolbar_drag || g_slider_drag || g_picker_drag!=0;
   if(!down && g_mouse_in && HitUI(x,y))want=true;
   if(want)HoldScroll();else if(!down)ReleaseScroll();
  }
void HandlePointer(const int x,const int y,const bool down)
  {
   bool was_down=g_prev_down;
   g_mouse_x=x;g_mouse_y=y;g_mouse_in=(x>=0 && y>=0 && x<g_width && y<g_height);
   g_last_mouse=GetTickCount64();
   PickerMouse(x,y,down,was_down);
   SliderMouse(x,y,down,was_down);
   if(down && !was_down)BeginMouse(x,y);
   else if(down && (g_drag!=0 || g_toolbar_drag))MoveMouse(x,y);
   else if(down)g_view_probe=true;
   else if(was_down || g_drag!=0 || g_toolbar_drag)FinishPointer(x,y);
   if((down || was_down) && g_drag==0 && !g_toolbar_drag && !g_editor && g_popup==0 && !HitUI(x,y))
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
   if(!ParseHotkey(InpPanelHotkey,g_panel_key,g_panel_ctrl,g_panel_shift,g_panel_alt) || !ParseHotkey(InpDuplicateHotkey,g_duplicate_key,g_duplicate_ctrl,g_duplicate_shift,g_duplicate_alt) || SameShortcut())
     {Print("Fibonacci Pro: use two different shortcuts, e.g. Ctrl+Shift+H and Ctrl+Shift+D (letters, digits or F1..F12).");return INIT_PARAMETERS_INCORRECT;}
   g_tf=TFIndex((ENUM_TIMEFRAMES)_Period);
   if(g_tf<0){Print("Fibonacci Pro: unsupported chart timeframe.");return INIT_FAILED;}
   g_frame_ms=Lim(InpFrameMilliseconds,16,100);
   g_ws_prefix="FP5."+WorkspaceTag()+".";
   g_token=MakeToken();
   g_prefix=g_ws_prefix+g_token+".";
   g_alive=g_ws_prefix+"Alive";
   string key=StringLen(InpStorageKey)>0?SafeName(InpStorageKey):IntegerToString(ChartID());
   FolderCreate("FibonacciPro");
   FolderCreate("FibonacciPro\\Presets");
   g_last_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".last.fpp";
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
   // MT5 can deliver a mouse event before its chart projection has updated.
   // Poll each frame during chart panning and for 150 ms after the last pan event.
   if(g_view_probe || now<g_fast_view_until || now-g_last_view>=200)
     {if(ViewChanged())g_dirty=true;g_last_view=now;g_view_probe=false;}
   bool changed=false;
   if(g_dirty && now>=g_render_retry_after){Render();changed=true;}
   // Leave a short grace period for queued native OBJECT_CLICK events.
   if(g_ui_dirty && !g_prev_down && !g_toolbar_drag && g_drag==0 && !g_slider_drag && now>=g_ui_defer_until)
     {ClosePopup();BuildUI();changed=true;}
   else if(g_status_dirty || (g_status_shown && now>=g_status_until))
     {UpdateStatusObjects(now);changed=true;}
   if(g_hover_pending){if(UpdateHover())changed=true;}
   else if(g_tip_visible && now-g_last_mouse>FP_TIP_IDLE_MS){if(HideTip())changed=true;}
   if(changed)ChartRedraw();
  }
void OnTimer(){RefreshFrame();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(g_detaching || !g_owner)return;
   if(id==CHARTEVENT_CHART_CHANGE){g_fast_view_until=GetTickCount64()+150;RefreshFrame(true);return;}
   if(id==CHARTEVENT_OBJECT_ENDEDIT){if(sparam==Obj("R.Name"))HarvestPresetName();else if(g_popup==0)EndEdit(sparam);return;}
   if(id==CHARTEVENT_CLICK)
     {if(g_prev_down || g_drag!=0 || g_toolbar_drag)FinishPointer((int)lparam,(int)dparam);return;}
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(g_prev_down || g_drag!=0 || g_toolbar_drag)FinishPointer((int)lparam,(int)dparam);
      if(StringFind(sparam,g_prefix)==0)Click(sparam);
      else if(StringFind(sparam,"FP5.")!=0 && !g_editor && g_drag==0 && g_selected>=0){g_selected=-1;g_dirty=true;g_ui_dirty=true;}
      RefreshFrame();
      return;
     }
   if(id==CHARTEVENT_KEYUP)
     {if((int)lparam==g_panel_key)g_panel_key_held=false;if((int)lparam==g_duplicate_key)g_duplicate_key_held=false;return;}
   if(id==CHARTEVENT_KEYDOWN)
     {
      int key=(int)lparam;
      if(key==27){if(g_popup!=0)ClosePopup();else if(g_editor)CloseEditor();else CancelDrag();HideTip();return;}
      bool ctrl=(TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL)&0x8000)!=0;
      bool shift=(TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT)&0x8000)!=0;
      bool alt=(TerminalInfoInteger(TERMINAL_KEYSTATE_MENU)&0x8000)!=0;
      // Bare-letter shortcuts must not fire while the user types properties.
      if(g_editor && !ctrl && !alt)return;
      if(FPShortcutMatch(key,g_panel_key,ctrl,shift,alt,g_panel_ctrl,g_panel_shift,g_panel_alt))
        {if(!g_panel_key_held){g_panel_key_held=true;ToggleUI();}return;}
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
