// Fibonacci Pro 1.50 -- custom drawing indicator for MetaTrader 5.
// No trading functions, DLLs, network access or external fonts/assets.
// Install in MQL5/Indicators, compile with the current MetaEditor 5.
#property copyright "Custom implementation for the user"
#property version   "1.50"
#property description "Independent Fibonacci anchors, horizontal drawers, per-level styling and alpha fill."
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#include <Canvas\Canvas.mqh>

input string InpWorkspace="Main";     // Unique name for this chart instance
input string InpStorageKey="";        // Optional stable key across recreated charts
input bool   InpSnapOHLC=true;         // Magnet near OHLC; otherwise anchor freely
input int    InpSnapRadiusPixels=5;   // OHLC magnet radius in chart pixels (0..50)
input int    InpFrameMilliseconds=16;  // Requested redraw interval (16..100 ms)
input double InpUIScale=1.0;           // Panel scaling (0.75..2.0)
input color  InpDefaultColor=clrDarkOrange;
input int    InpMaximumSetups=24;      // 1..24 drawings per workspace
input string InpPanelHotkey="Ctrl+Shift+H";     // Hide/show the full tool interface
input string InpDuplicateHotkey="Ctrl+Shift+D"; // Duplicate highlighted custom Fib

#define FP_TOOLBAR_WIDTH 418
#define FP_TOOLBAR_HEIGHT 49
#define FP_MAX_SETUPS 24
#define FP_MAX_LEVELS 64
#define FP_MAGIC 1179668785
#define FP_END 1179668799
#define FP_SCHEMA 1
#define FP_PRESET_MAGIC 1179668801
#define FP_PRESET_END 1179668809
#define FP_LAYOUT_MAGIC 1179668811

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
   long visible_mask;
   int visibility_mode;            // 0 custom subset, 1 all allowed, 2 source only
   bool ray_left,ray_right;
   bool anchors_locked;
   bool diagonal,labels;
   color base_color;
   bool fill,gradient,fill_rays;
   color fill_top,fill_bottom;
   int opacity;
   int count;
   FPLevel levels[FP_MAX_LEVELS];
  };

// PURE_GEOMETRY_BEGIN -- compiled directly by the included local test harness.
double FPLevelPrice(const double pa,const double pb,const double ratio)
  { return pb+ratio*(pa-pb); }
long FPAllowedMask(const int source_index)
  { return (source_index<0 || source_index>20)?0:(((long)1<<(source_index+1))-1); }
long FPAdaptMask(const long mask,const int source_index,const int target_index,const int mode=-1)
  {
   if(source_index<0 || target_index<0)return 0;
   long allowed=FPAllowedMask(target_index),source_allowed=FPAllowedMask(source_index);
   if(mode==1)return allowed;
   if(mode==2)return (long)1<<target_index;
   if(mode==0)return mask&allowed;
   if(mask==source_allowed)return allowed;
   if(mask==((long)1<<source_index))return (long)1<<target_index;
   return mask&allowed;
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
// PURE_GEOMETRY_END

FPSetup g_sets[FP_MAX_SETUPS],g_stage[FP_MAX_SETUPS],g_edit,g_drag_backup,g_last_config;
bool g_has_last_config=false,g_edit_error=false,g_last_config_persisted=false;
int g_count=0,g_next_uid=1,g_selected=-1,g_tab=2,g_page=0,g_rows=9;
bool g_editor=false,g_hidden=false,g_armed=false,g_dirty=true,g_ui_dirty=true;
bool g_prev_down=false,g_scroll_held=false,g_scroll_before=true,g_old_mouse=false;
int g_drag=0,g_created=-1,g_previous_selection=-1,g_drag_x=0,g_drag_y=0;
datetime g_drag_time=0;double g_drag_price=0;
int g_width=0,g_height=0,g_panel_x=16,g_panel_y=62;
double g_scale=1.0;
bool g_detaching=false;
string g_shortname;
string g_prefix,g_store,g_last_store,g_layout_store,g_status="New Fib: press, drag and release.";
CCanvas g_fill_canvas,g_line_canvas,g_picker;
bool g_canvas_ready=false,g_picker_ready=false,g_fill_visible=false;
ulong g_ui_defer_until=0,g_render_retry_after=0;
bool g_primary_valid=false,g_view_probe=true;
int g_file_lock=INVALID_HANDLE;
int g_popup=0,g_popup_row=-1,g_popup_x=0,g_popup_y=0; // 1 style, 2 width, 3 palette
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
bool Visible(FPSetup &s)
  {int i=TFIndex((ENUM_TIMEFRAMES)_Period);return i>=0 && (s.visible_mask & Allowed(s.source_tf) & ((long)1<<i))!=0;}
int MaxSetups(){return Lim(InpMaximumSetups,1,FP_MAX_SETUPS);}
string Obj(const string tail){return g_prefix+tail;}
string UIS(const string tail){return Obj("U."+tail);}
string SafeName(string value)
  {
   string forbidden="\\/:*?\"<>|\r\n\t";
   for(int i=0;i<StringLen(forbidden);i++)StringReplace(value,StringSubstr(forbidden,i,1),"_");
   return StringSubstr(value,0,80);
  }
string RatioText(const double value)
  {
   string text=DoubleToString(value,16);
   while(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)=="0")text=StringSubstr(text,0,StringLen(text)-1);
   if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)==".")text=StringSubstr(text,0,StringLen(text)-1);
   return text;
  }
void Status(const string value)
  {
   g_status=value;
   if(ObjectFind(0,UIS("T.Grip"))>=0)
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
void Defaults(FPSetup &s)
  {
   double ratios[]={0,.236,.382,.5,.618,.786,1};
   s.count=ArraySize(ratios);
   for(int i=0;i<s.count;i++)
     {s.levels[i].enabled=true;s.levels[i].value=ratios[i];s.levels[i].description="%%  (%$)";
      s.levels[i].style=STYLE_SOLID;s.levels[i].width=1;s.levels[i].ink=InpDefaultColor;}
  }
// CONFIG_LOGIC_BEGIN -- production functions also exercised by local tests.
void CopyConfig(FPSetup &target,FPSetup &source)
  {
   target.ray_left=source.ray_left;target.ray_right=source.ray_right;
   target.anchors_locked=source.anchors_locked;target.diagonal=source.diagonal;target.labels=source.labels;
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
   if(a.fill!=b.fill || a.gradient!=b.gradient || a.fill_rays!=b.fill_rays || a.fill_top!=b.fill_top || a.fill_bottom!=b.fill_bottom || a.opacity!=b.opacity || a.visible_mask!=b.visible_mask || a.visibility_mode!=b.visibility_mode || a.source_tf!=b.source_tf || a.count!=b.count)return false;
   for(int i=0;i<a.count;i++)
     {if(a.levels[i].enabled!=b.levels[i].enabled || a.levels[i].value!=b.levels[i].value || a.levels[i].description!=b.levels[i].description || a.levels[i].style!=b.levels[i].style || a.levels[i].width!=b.levels[i].width || a.levels[i].ink!=b.levels[i].ink)return false;}
   return true;
  }
// CONFIG_LOGIC_END
void NewSetup(FPSetup &s)
  {
   s.uid=g_next_uid++;s.name="Fibo "+IntegerToString(s.uid);s.description="";
   s.ta=0;s.tb=0;s.pa=0;s.pb=0;s.left=0;s.right=0;
   s.source_tf=(ENUM_TIMEFRAMES)_Period;s.visible_mask=Allowed(s.source_tf);s.visibility_mode=1;
   s.ray_left=false;s.ray_right=false;s.anchors_locked=false;s.diagonal=true;s.labels=true;
   s.base_color=InpDefaultColor;s.fill=false;s.gradient=false;s.fill_rays=true;
   s.fill_top=clrRoyalBlue;s.fill_bottom=clrPowderBlue;s.opacity=12;Defaults(s);
   if(g_has_last_config)CopyConfig(s,g_last_config);
  }
void HoldScroll()
  {if(!g_scroll_held){g_scroll_before=(bool)ChartGetInteger(0,CHART_MOUSE_SCROLL);ChartSetInteger(0,CHART_MOUSE_SCROLL,false);g_scroll_held=true;}}
void ReleaseScroll()
  {if(g_scroll_held){ChartSetInteger(0,CHART_MOUSE_SCROLL,g_scroll_before);g_scroll_held=false;}}
bool XY(const datetime t,const double p,int &x,int &y)
  {return ChartTimePriceToXY(0,0,t,p,x,y);}
bool Point(const int x,const int y,datetime &t,double &p)
  {int sub=-1;bool ok=ChartXYToTimePrice(0,x,y,sub,t,p) && sub==0 && MathIsValidNumber(p);if(ok)p=NormalizeDouble(p,_Digits);return ok;}
bool Snap(const int x,const int y,const ENUM_TIMEFRAMES tf,datetime &t,double &p)
  {
   if(!Point(x,y,t,p))return false;
   if(!InpSnapOHLC)return true;
   int shift=iBarShift(_Symbol,tf,t,false);
   if(shift<0)return true; // Missing history must not block free placement.
   int radius=Lim(InpSnapRadiusPixels,0,50);
   if(radius==0)return true;
   double best=(double)radius*radius;
   datetime snap_time=t;double snap_price=p;bool found=false;
   for(int k=(int)MathMax(0,shift-1);k<=shift+1;k++)
     {
      MqlRates rates[1];
      if(CopyRates(_Symbol,tf,k,1,rates)!=1)continue;
      double prices[4];prices[0]=rates[0].open;prices[1]=rates[0].high;prices[2]=rates[0].low;prices[3]=rates[0].close;
      for(int q=0;q<4;q++)
        {
         int px=0,py=0;if(!XY(rates[0].time,prices[q],px,py))continue;
         double distance=(double)(px-x)*(px-x)+(double)(py-y)*(py-y);
         if(distance<=best){best=distance;snap_time=rates[0].time;snap_price=prices[q];found=true;}
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
   s.base_color=(color)FileReadInteger(f);s.fill_top=(color)FileReadInteger(f);s.fill_bottom=(color)FileReadInteger(f);s.opacity=FileReadInteger(f);s.count=FileReadInteger(f);
   if(s.uid<=0 || s.ta<=0 || s.tb<=0 || s.left>=s.right || TFIndex(s.source_tf)<0 || s.count<0 || s.count>FP_MAX_LEVELS || s.opacity<0 || s.opacity>100)return false;
   if(!MathIsValidNumber(s.pa) || !MathIsValidNumber(s.pb) || s.pa==s.pb)return false;
   s.visible_mask&=Allowed(s.source_tf);
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
   if(g_store=="")return false;
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
   record.uid=1;record.name="Configuration";record.description="";
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
   if(g_has_last_config && g_last_config_persisted && SameConfig(settings,g_last_config))return true;
   g_last_config=settings;g_has_last_config=true;
   g_last_config_persisted=WritePreset(g_last_store,g_last_config);
   if(g_last_config_persisted)return true;
   Status("Drawing settings kept in memory; saving last-used configuration failed.");
   Print("Fibonacci Pro could not persist last-used configuration: ",GetLastError());return false;
  }
void SaveLayout()
  {
   if(g_layout_store=="")return;
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
void DeletePrefix(const string prefix){ObjectsDeleteAll(0,prefix);}
void UIBase(const string name,const ENUM_OBJECT type,const int x,const int y,const int w,const int h,const string text,const color bg=clrWhite,const color fg=clrBlack)
  {
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,type,0,0,0))return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   if(type!=OBJ_LABEL){ObjectSetInteger(0,name,OBJPROP_XSIZE,w);ObjectSetInteger(0,name,OBJPROP_YSIZE,h);}
   ObjectSetInteger(0,name,OBJPROP_COLOR,type==OBJ_RECTANGLE_LABEL?clrSilver:fg);
   if(type!=OBJ_LABEL)ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   if(type==OBJ_BUTTON || type==OBJ_EDIT)ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
   if(type!=OBJ_RECTANGLE_LABEL)
     {ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(int)MathMax(8,U(9)));ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI");ObjectSetString(0,name,OBJPROP_TEXT,text);}
   if(type==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
   if(type==OBJ_EDIT){ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_LEFT);ObjectSetInteger(0,name,OBJPROP_READONLY,false);}
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
  {UIBase(UIS(key),OBJ_RECTANGLE_LABEL,x,y,U(w),U(h),"",bg);ObjectSetInteger(0,UIS(key),OBJPROP_ZORDER,90);ObjectSetInteger(0,UIS(key),OBJPROP_BORDER_TYPE,BORDER_FLAT);}
int PanelHeight(){return U(184+g_rows*24);}
void ClosePopup()
  {DeletePrefix(Obj("P."));DeletePrefix(Obj("D."));DeletePrefix(Obj("R."));if(g_picker_ready){g_picker.Destroy();g_picker_ready=false;}g_popup=0;g_picker_drag=0;}
void CloseEditor()
  {ClosePopup();g_editor=false;DeletePrefix(UIS("E."));g_ui_dirty=true;g_dirty=true;}
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
   g_edit.visible_mask&=Allowed(g_edit.source_tf);
   FPSetup previous=g_sets[g_selected];g_sets[g_selected]=g_edit;
   if(!Save()){g_sets[g_selected]=previous;g_dirty=true;return false;}
   if(!RememberConfig(g_edit)){g_dirty=true;return false;}
   g_dirty=true;Status("Drawing and last-used configuration saved.");
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
   if(g_count>=MaxSetups()){Status("Drawing limit reached; delete a drawing first.");return;}
   FPSetup source=g_sets[g_selected];
   if(g_editor){if(!HarvestEdits())return;source=g_edit;}
   if(!Visible(source)){Status("Highlight a visible custom Fib before duplicating.");return;}
   int slot=g_count,uid=g_next_uid;
   CopyDuplicate(g_sets[slot],source,uid);g_count++;g_next_uid++;
   if(!Save()){g_count--;g_next_uid--;return;}
   CloseEditor();g_selected=slot;g_dirty=true;g_ui_dirty=true;
   if(RememberConfig(g_sets[slot]))Status("Duplicate selected at the same anchors. Drag its middle handle to move it.");
  }
void BuildUI()
  {
   g_ui_dirty=false;
   // Toolbar objects have stable identities: never delete a pressed button.
   DeletePrefix(UIS("E."));
   if(g_hidden){DeletePrefix(UIS("T."));return;}
   int x=g_toolbar_x,y=g_toolbar_y;
   // No toolbar background object: the chart remains visible between controls.
   color text_color=(color)ChartGetInteger(0,CHART_COLOR_FOREGROUND);
   Label("T.Grip",":: Fibonacci Pro   (drag to move)",x+U(7),y+U(3),text_color);
   string title=g_selected>=0 && g_selected<g_count?g_sets[g_selected].name:"No selection";
   ObjectSetString(0,UIS("T.Grip"),OBJPROP_TOOLTIP,title+" | "+g_status+" | Drag title to move");
   Button("T.Close","×",x+U(FP_TOOLBAR_WIDTH-28),y+U(1),20,18);
   ObjectSetString(0,UIS("T.Close"),OBJPROP_TOOLTIP,"Detach Fibonacci Pro from this chart (saved drawings retained)");
   x+=U(8);y+=U(23);
   Button("T.New",g_armed?"Draw now...":"New Fib",x,y,78);x+=U(80);
   Button("T.Prev","<",x,y,23);x+=U(25);
   Button("T.Next",">",x,y,23);x+=U(25);
   Button("T.Properties","Properties",x,y,82);x+=U(84);
   Button("T.Duplicate","Duplicate",x,y,72);x+=U(74);
   Button("T.Delete","Delete",x,y,52);x+=U(54);
   Button("T.Hide","Hide UI",x,y,60);
   // Status stays in the grip tooltip instead of widening the compact toolbar.
   if(!g_editor)return;
   x=g_panel_x;y=g_panel_y;
   Box("E.Background",x,y,488,184+g_rows*24,clrWhiteSmoke);
   Label("E.Title","Fibonacci Pro - "+g_edit.name,x+U(10),y+U(7));
   string tabs[]={"Common","Parameters","Fibo levels","Visualization","Fill"};
   int widths[]={72,91,90,104,55};int tx=x+U(10);
   for(int t=0;t<5;t++){Button("E.Tab"+IntegerToString(t),tabs[t],tx,y+U(30),widths[t],23,t==g_tab?clrWhite:clrGainsboro);tx+=U(widths[t]+2);}
   int cy=y+U(64);
   if(g_tab==0)
     {
      Label("E.NL","Name",x+U(12),cy+U(4));Edit("E.Name",g_edit.name,x+U(95),cy,350);cy+=U(28);
      Label("E.DL","Description",x+U(12),cy+U(4));Edit("E.Description",g_edit.description,x+U(95),cy,350);cy+=U(32);
      Check("E.Labels","Show level labels",g_edit.labels,x+U(12),cy,200);cy+=U(27);
      Check("E.Diagonal","Show anchor diagonal",g_edit.diagonal,x+U(12),cy,200);cy+=U(27);
      Check("E.Lock","Lock price-anchor handles",g_edit.anchors_locked,x+U(12),cy,240);cy+=U(30);
      Button("E.BaseColor","Diagonal color",x+U(12),cy,130,22,g_edit.base_color);
     }
   if(g_tab==1)
     {
      Label("E.TF","Drawn on "+g_tf_names[TFIndex(g_edit.source_tf)]+" (fixed)",x+U(12),cy);cy+=U(29);
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
      Label("E.VTitle","Drawing timeframe and below only",x+U(12),cy);cy+=U(30);
      int source=TFIndex(g_edit.source_tf);
      for(int i=0;i<21;i++)
        {
         string text=(i<=source?(((g_edit.visible_mask&((long)1<<i))!=0)?"[x] ":"[ ] "):"-- ")+g_tf_names[i];
         Button("E.TF"+IntegerToString(i),text,x+U(12+(i%5)*90),cy+U((i/5)*30),84,24,i<=source?clrWhite:clrGainsboro);
        }
      Button("E.AllLower","All allowed",x+U(12),cy+U(159),120);Button("E.OnlySource","Drawing TF only",x+U(136),cy+U(159),150);
     }
   if(g_tab==4)
     {
      Check("E.Fill","Enable transparent fill",g_edit.fill,x+U(12),cy,230);cy+=U(29);
      Check("E.Gradient","Vertical gradient",g_edit.gradient,x+U(12),cy,230);cy+=U(29);
      Check("E.FillRays","Fill follows left/right rays",g_edit.fill_rays,x+U(12),cy,260);cy+=U(32);
      Button("E.FillTop","Top / solid color",x+U(12),cy,180,24,g_edit.fill_top);
      Button("E.FillBottom","Bottom color",x+U(198),cy,180,24,g_edit.fill_bottom);cy+=U(36);
      Label("E.OpacityLabel","Opacity 0-100%",x+U(12),cy+U(4));Edit("E.Opacity",IntegerToString(g_edit.opacity),x+U(170),cy,65);
     }
   int by=y+PanelHeight()-U(31);
   Button("E.Save","Save",x+U(316),by-U(30),72);Button("E.Load","Load",x+U(390),by-U(30),72);
   Button("E.OK","OK",x+U(242),by,72);Button("E.Cancel","Cancel",x+U(316),by,72);Button("E.Apply","Apply",x+U(390),by,72);
  }

void RefreshPresetList()
  {
   g_preset_count=0;string filename;
   long search=FileFindFirst("FibonacciPro\\Presets\\*.fpp",filename);
   if(search!=INVALID_HANDLE)
     {
      do
        {int n=StringLen(filename);if(n>4 && g_preset_count<256)g_preset_names[g_preset_count++]=StringSubstr(filename,0,n-4);}
      while(FileFindNext(search,filename));
      FileFindClose(search);
     }
   for(int i=0;i<g_preset_count-1;i++)for(int j=i+1;j<g_preset_count;j++)
     if(StringCompare(g_preset_names[i],g_preset_names[j])>0){string temp=g_preset_names[i];g_preset_names[i]=g_preset_names[j];g_preset_names[j]=temp;}
  }
void PresetMessage(const string text)
  {ObjectSetString(0,Obj("R.Message"),OBJPROP_TEXT,StringSubstr(text,0,48));ChartRedraw();}
void HarvestPresetName()
  {if(ObjectFind(0,Obj("R.Name"))>=0)g_preset_name=ObjectGetString(0,Obj("R.Name"),OBJPROP_TEXT);}
void PresetBrowser(const bool save_mode,const bool reset_page=true)
  {
   if(!g_editor)return;
   if(g_popup==4)HarvestPresetName();
   ClosePopup();g_popup=4;g_preset_save=save_mode;
   if(reset_page){RefreshPresetList();g_preset_page=0;}
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(20);
   if(g_popup_y+U(326)>g_height)g_popup_y=(int)MathMax(4,g_height-U(326)-4);
   UIBase(Obj("R.Background"),OBJ_RECTANGLE_LABEL,g_popup_x,g_popup_y,U(360),U(326),"",clrWhiteSmoke);
   ObjectSetInteger(0,Obj("R.Background"),OBJPROP_BORDER_TYPE,BORDER_FLAT);
   UIBase(Obj("R.Title"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(8),0,0,save_mode?"Save configuration preset":"Load configuration preset");
   UIBase(Obj("R.Name"),OBJ_EDIT,g_popup_x+U(10),g_popup_y+U(34),U(338),U(24),g_preset_name);
   for(int row=0;row<7;row++)
     {
      int i=g_preset_page*7+row;if(i>=g_preset_count)break;
      UIBase(Obj("R.Item"+IntegerToString(i)),OBJ_BUTTON,g_popup_x+U(10),g_popup_y+U(68+row*23),U(338),U(22),g_preset_names[i]);
     }
   UIBase(Obj("R.Prev"),OBJ_BUTTON,g_popup_x+U(10),g_popup_y+U(236),U(28),U(23),"<");
   UIBase(Obj("R.Next"),OBJ_BUTTON,g_popup_x+U(40),g_popup_y+U(236),U(28),U(23),">");
   UIBase(Obj("R.Page"),OBJ_LABEL,g_popup_x+U(80),g_popup_y+U(240),0,0,IntegerToString(g_preset_page+1)+" / "+IntegerToString((int)MathMax(1,(g_preset_count+6)/7)));
   UIBase(Obj("R.Message"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(267),0,0,save_mode?"Choose a name; saving replaces that named preset.":"Choose a saved preset; anchors stay unchanged.");
   UIBase(Obj("R.Action"),OBJ_BUTTON,g_popup_x+U(184),g_popup_y+U(292),U(80),U(24),save_mode?"Save":"Load");
   UIBase(Obj("R.Cancel"),OBJ_BUTTON,g_popup_x+U(268),g_popup_y+U(292),U(80),U(24),"Cancel");
   for(int i=ObjectsTotal(0)-1;i>=0;i--){string n=ObjectName(0,i);if(StringFind(n,Obj("R."))==0)ObjectSetInteger(0,n,OBJPROP_ZORDER,n==Obj("R.Background")?390:400);}
   ChartRedraw();
  }
void PresetAction()
  {
   if(!g_editor || g_popup!=4)return;
   HarvestPresetName();StringTrimLeft(g_preset_name);StringTrimRight(g_preset_name);
   if(g_preset_name=="" || StringLen(g_preset_name)>80 || SafeName(g_preset_name)!=g_preset_name || g_preset_name=="." || g_preset_name==".." || StringSubstr(g_preset_name,StringLen(g_preset_name)-1)==".")
     {PresetMessage("Use a short name without path or special characters.");return;}
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

void Dropdown(const int kind,const int row)
  {
   if(!g_editor || row<0 || row>=g_edit.count)return;
   ClosePopup();g_popup=kind;g_popup_row=row;
   string source=UIS("E."+(kind==1?"Style":"Width")+IntegerToString(row));
   g_popup_x=(int)ObjectGetInteger(0,source,OBJPROP_XDISTANCE);
   g_popup_y=(int)ObjectGetInteger(0,source,OBJPROP_YDISTANCE)+U(23);
   if(g_popup_y+U(116)>g_height)g_popup_y-=U(140);
   for(int i=0;i<5;i++)
     {
      string n=Obj("D."+IntegerToString(i));UIBase(n,OBJ_BUTTON,g_popup_x,g_popup_y+U(23*i),U(kind==1?110:48),U(23),kind==1?g_style_names[i]:IntegerToString(i+1));
      ObjectSetInteger(0,n,OBJPROP_ZORDER,300);
     }
   ChartRedraw();
  }
void RGBtoHSV(const color ink)
  {
   double r=((int)ink&255)/255.0,g=(((int)ink>>8)&255)/255.0,b=(((int)ink>>16)&255)/255.0;
   double hi=MathMax(r,MathMax(g,b)),lo=MathMin(r,MathMin(g,b)),d=hi-lo;
   g_value=hi;g_saturation=hi==0?0:d/hi;g_hue=0;
   if(d>0){if(hi==r)g_hue=60*MathMod((g-b)/d,6);else if(hi==g)g_hue=60*((b-r)/d+2);else g_hue=60*((r-g)/d+4);}
   if(g_hue<0)g_hue+=360;
  }
void DrawPicker()
  {
   if(!g_picker_ready)return;
   int w=g_picker.Width(),h=g_picker.Height(),square=w-U(34);
   g_picker.Erase(ColorToARGB(clrWhite));
   for(int y=0;y<h;y++)for(int x=0;x<square;x++)g_picker.PixelSet(x,y,ColorToARGB(FPHSV(g_hue,(double)x/MathMax(1,square-1),1.0-(double)y/MathMax(1,h-1))));
   for(int y=0;y<h;y++)g_picker.FillRectangle(square+U(10),y,w-1,y,ColorToARGB(FPHSV((double)y/MathMax(1,h-1)*359.99,1,1)));
   int sx=(int)MathRound(g_saturation*(square-1)),sy=(int)MathRound((1-g_value)*(h-1));
   g_picker.Rectangle(Lim(sx-3,0,square-1),Lim(sy-3,0,h-1),Lim(sx+3,0,square-1),Lim(sy+3,0,h-1),ColorToARGB(clrBlack));
   g_picker.Update(false);
   ObjectSetInteger(0,Obj("P.Sample"),OBJPROP_BGCOLOR,g_pick_color);
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
   string n=Obj("P.BG");UIBase(n,OBJ_RECTANGLE_LABEL,g_popup_x,g_popup_y,U(360),U(354),"",clrWhiteSmoke);ObjectSetInteger(0,n,OBJPROP_ZORDER,350);
   UIBase(Obj("P.Title"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(7),0,0,"All MT5 named colors + visual spectrum");
   ObjectSetInteger(0,Obj("P.Title"),OBJPROP_ZORDER,360);
   for(int i=0;i<ArraySize(g_palette);i++)
     {
      n=Obj("P.Color"+IntegerToString(i));UIBase(n,OBJ_BUTTON,g_popup_x+U(10+(i%18)*19),g_popup_y+U(30+(i/18)*19),U(18),U(18),"",g_palette[i]);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,g_color_names[i]);ObjectSetInteger(0,n,OBJPROP_ZORDER,360);
     }
   g_picker_ready=g_picker.CreateBitmapLabel(0,0,Obj("P.Spectrum"),g_popup_x+U(12),g_popup_y+U(193),U(334),U(112),COLOR_FORMAT_ARGB_NORMALIZE);
   if(g_picker_ready){ObjectSetInteger(0,Obj("P.Spectrum"),OBJPROP_ZORDER,370);ObjectSetInteger(0,Obj("P.Spectrum"),OBJPROP_SELECTABLE,false);ObjectSetInteger(0,Obj("P.Spectrum"),OBJPROP_HIDDEN,true);}
   UIBase(Obj("P.Sample"),OBJ_BUTTON,g_popup_x+U(12),g_popup_y+U(316),U(80),U(25),"",g_pick_color);
   UIBase(Obj("P.Use"),OBJ_BUTTON,g_popup_x+U(170),g_popup_y+U(316),U(85),U(25),"Use color");
   UIBase(Obj("P.Cancel"),OBJ_BUTTON,g_popup_x+U(259),g_popup_y+U(316),U(85),U(25),"Cancel");
   ObjectSetInteger(0,Obj("P.Sample"),OBJPROP_ZORDER,370);ObjectSetInteger(0,Obj("P.Use"),OBJPROP_ZORDER,370);ObjectSetInteger(0,Obj("P.Cancel"),OBJPROP_ZORDER,370);
   DrawPicker();ChartRedraw();
  }
void PickerMouse(const int x,const int y,const bool down,const bool was_down)
  {
   if(g_popup!=3 || !g_picker_ready)return;
   int sx=g_popup_x+U(12),sy=g_popup_y+U(193),w=g_picker.Width(),h=g_picker.Height(),square=w-U(34);
   if(down && !was_down && x>=sx && x<sx+w && y>=sy && y<sy+h)g_picker_drag=(x<sx+square)?1:2;
   if(!down){g_picker_drag=0;return;}
   if(g_picker_drag==1){g_saturation=(double)Lim(x-sx,0,square-1)/(square-1);g_value=1.0-(double)Lim(y-sy,0,h-1)/(h-1);}
   else if(g_picker_drag==2)g_hue=(double)Lim(y-sy,0,h-1)/(h-1)*359.99;
   else return;
   g_pick_color=FPHSV(g_hue,g_saturation,g_value);DrawPicker();
  }

bool EnsureCanvases()
  {
   if(g_width<2 || g_height<2)return false;
   if(g_canvas_ready && g_line_canvas.Width()==g_width && g_line_canvas.Height()==g_height)return true;
   g_fill_canvas.Destroy();g_line_canvas.Destroy();g_canvas_ready=false;g_fill_visible=false;
   if(!g_fill_canvas.CreateBitmapLabel(0,0,Obj("Fill"),0,0,g_width,g_height,COLOR_FORMAT_ARGB_NORMALIZE))return false;
   if(!g_line_canvas.CreateBitmapLabel(0,0,Obj("Lines"),0,0,g_width,g_height,COLOR_FORMAT_ARGB_NORMALIZE)){g_fill_canvas.Destroy();return false;}
   g_fill_canvas.Erase(0);g_fill_canvas.Update(false); // Initial transparent resource.
   string names[2];names[0]=Obj("Fill");names[1]=Obj("Lines");
   for(int i=0;i<2;i++)
     {ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,false);ObjectSetInteger(0,names[i],OBJPROP_HIDDEN,true);ObjectSetInteger(0,names[i],OBJPROP_ZORDER,0);ObjectSetString(0,names[i],OBJPROP_TOOLTIP,"\n");}
   ObjectSetInteger(0,names[0],OBJPROP_BACK,true);ObjectSetInteger(0,names[1],OBJPROP_BACK,false);
   g_line_canvas.FontSet("Segoe UI",-U(12));g_canvas_ready=true;return true;
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
   for(int i=0;i<=length;i+=6)
     {double a=(double)i/length,b=(double)MathMin(length,i+2)/length;
      g_line_canvas.Line((int)MathRound(x0+dx*a),(int)MathRound(y0+dy*a),(int)MathRound(x0+dx*b),(int)MathRound(y0+dy*b),ColorToARGB(ink));}
  }
void Grip(const int x,const int y,const color ink)
  {
   if(x<0 || x>=g_width || y<0 || y>=g_height)return;
   g_line_canvas.FillRectangle(Lim(x-1,0,g_width-1),Lim(y-1,0,g_height-1),Lim(x+1,0,g_width-1),Lim(y+1,0,g_height-1),ColorToARGB(ink));
  }
string LevelText(FPLevel &level,const double price)
  {string s=level.description;StringReplace(s,"%%",DoubleToString(level.value*100,1));StringReplace(s,"%$",DoubleToString(price,_Digits));return s;}
void RenderSetup(FPSetup &s,const bool selected)
  {
   if(!Visible(s))return;
   int xa=0,ya=0,xb=0,yb=0,xl=0,xr=0;
   if(!Geometry(s,xa,ya,xb,yb,xl,xr))return;
   int l=s.ray_left?0:xl,r=s.ray_right?g_width-1:xr;
   if(s.fill && s.opacity>0)
     {
      int fl=s.fill_rays?l:xl,fr=s.fill_rays?r:xr;
      int top=(int)MathMin(ya,yb),bottom=(int)MathMax(ya,yb);
      if(fr>=0 && fl<g_width && bottom>=0 && top<g_height)
        {
         int x0=Lim(fl,0,g_width-1),x1=Lim(fr,0,g_width-1),y0=Lim(top,0,g_height-1),y1=Lim(bottom,0,g_height-1);
         uchar alpha=(uchar)MathRound(s.opacity*255.0/100.0);
         if(x0<=x1)
           {
            if(!s.gradient)g_fill_canvas.FillRectangle(x0,y0,x1,y1,ColorToARGB(s.fill_top,alpha));
            else for(int y=y0;y<=y1;y++)g_fill_canvas.FillRectangle(x0,y,x1,y,ColorToARGB(FPBlend(s.fill_top,s.fill_bottom,(double)(y-top)/MathMax(1,bottom-top)),alpha));
           }
        }
     }
   for(int i=0;i<s.count;i++)
     {
      if(!s.levels[i].enabled)continue;
      double price=FPLevelPrice(s.pa,s.pb,s.levels[i].value);int ignore=0,y=0;
      if(!XY(s.ta,price,ignore,y) || y<0 || y>=g_height)continue;
      HLine(l,r,y,s.levels[i].ink,s.levels[i].width,s.levels[i].style);
      if(s.labels && r>=0 && l<g_width)
        {
         string text=LevelText(s.levels[i],price);int tw=g_line_canvas.TextWidth(text),th=g_line_canvas.TextHeight(text);
         int tx=Lim(l+U(3),2,(int)MathMax(2,g_width-tw-2)),ty=Lim(y-th-2,0,(int)MathMax(0,g_height-th));
         g_line_canvas.TextOut(tx,ty,text,ColorToARGB(s.levels[i].ink));
        }
     }
   if(s.diagonal)Diagonal(xa,ya,xb,yb,s.base_color);
   if(selected)
     {
      color ink=s.anchors_locked?clrGray:s.base_color;
      Grip(xa,ya,ink);Grip(xb,yb,ink);Grip((int)(((long)xa+xb)/2),(int)(((long)ya+yb)/2),ink);
      int mid=Lim((int)(((long)ya+yb)/2),5,g_height-6);
      Grip(Lim(xl,5,g_width-6),mid,s.base_color);Grip(Lim(xr,5,g_width-6),mid,s.base_color);
     }
  }
void Render()
  {
   if(GetTickCount64()<g_render_retry_after)return;
   if(!EnsureCanvases())
     {g_render_retry_after=GetTickCount64()+1000;Status("Canvas creation failed; retrying. Check chart size/memory.");return;}
   g_render_retry_after=0;
   bool fill_needed=false;
   for(int i=0;i<g_count;i++)
     {
      FPSetup current=g_sets[i];if(g_editor && i==g_selected)current=g_edit;
      if(Visible(current) && current.fill && current.opacity>0){fill_needed=true;break;}
     }
   bool update_fill=fill_needed || g_fill_visible;
   if(update_fill)g_fill_canvas.Erase(0);
   g_line_canvas.Erase(0);
   // Unselected first, selected last for predictable selection and stacking.
   for(int i=0;i<g_count;i++)if(i!=g_selected)RenderSetup(g_sets[i],false);
   if(g_selected>=0 && g_selected<g_count){if(g_editor)RenderSetup(g_edit,true);else RenderSetup(g_sets[g_selected],true);}
   if(update_fill)g_fill_canvas.Update(false);
   g_fill_visible=fill_needed;g_line_canvas.Update(false);g_dirty=false;
  }
bool ViewChanged()
  {
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0),h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   long first=ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR),scale=ChartGetInteger(0,CHART_SCALE),bars=ChartGetInteger(0,CHART_VISIBLE_BARS);
   double lo=ChartGetDouble(0,CHART_PRICE_MIN,0),hi=ChartGetDouble(0,CHART_PRICE_MAX,0);
   datetime first_time=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,(int)first);
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

bool HitUI(const int x,const int y)
  {
   if(g_hidden)return false;
   if(y>=g_toolbar_y && y<=g_toolbar_y+U(FP_TOOLBAR_HEIGHT) && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH))return true;
   if(g_popup==4 && x>=g_popup_x && x<=g_popup_x+U(360) && y>=g_popup_y && y<=g_popup_y+U(326))return true;
   if(g_popup==3 && x>=g_popup_x && x<=g_popup_x+U(360) && y>=g_popup_y && y<=g_popup_y+U(354))return true;
   if(g_popup==1 || g_popup==2)if(x>=g_popup_x && x<=g_popup_x+U(110) && y>=g_popup_y && y<=g_popup_y+U(116))return true;
   return g_editor && x>=g_panel_x && x<=g_panel_x+U(488) && y>=g_panel_y && y<=g_panel_y+PanelHeight();
  }
double SegmentDistance(const int x,const int y,const int xa,const int ya,const int xb,const int yb)
  {
   double dx=(double)xb-xa,dy=(double)yb-ya,length=dx*dx+dy*dy;
   double t=length>0?MathMax(0,MathMin(1,((x-xa)*dx+(y-ya)*dy)/length)):0;
   return MathSqrt(MathPow(x-(xa+t*dx),2)+MathPow(y-(ya+t*dy),2));
  }
int HitHandle(FPSetup &s,const int x,const int y)
  {
   int xa=0,ya=0,xb=0,yb=0,xl=0,xr=0;if(!Visible(s) || !Geometry(s,xa,ya,xb,yb,xl,xr))return 0;
   int mid=Lim((int)(((long)ya+yb)/2),5,g_height-6),tol=U(7);
   // Anchors take priority if a drawer and anchor overlap on a small drawing.
   if(!s.anchors_locked)
     {
      if(MathAbs(x-xa)<=tol && MathAbs(y-ya)<=tol)return 2;
      if(MathAbs(x-xb)<=tol && MathAbs(y-yb)<=tol)return 3;
     }
   if(MathAbs(x-Lim(xl,5,g_width-6))<=tol && MathAbs(y-mid)<=tol)return 4;
   if(MathAbs(x-Lim(xr,5,g_width-6))<=tol && MathAbs(y-mid)<=tol)return 5;
   if(!s.anchors_locked && MathAbs(x-(int)(((long)xa+xb)/2))<=tol && MathAbs(y-(int)(((long)ya+yb)/2))<=tol)return 6;
   return 0;
  }
bool HitSetup(FPSetup &s,const int x,const int y)
  {
   if(!Visible(s))return false;
   int xa=0,ya=0,xb=0,yb=0,xl=0,xr=0;if(!Geometry(s,xa,ya,xb,yb,xl,xr))return false;
   if(s.diagonal && SegmentDistance(x,y,xa,ya,xb,yb)<=U(5))return true;
   int l=s.ray_left?0:xl,r=s.ray_right?g_width-1:xr;
   if(x<l-U(5) || x>r+U(5))return false;
   for(int i=0;i<s.count;i++)
     {int ignore=0,ly=0;if(s.levels[i].enabled && XY(s.ta,FPLevelPrice(s.pa,s.pb,s.levels[i].value),ignore,ly) && MathAbs(y-ly)<=U(5))return true;}
   return false;
  }
void Arm()
  {
   if(g_drag!=0)CancelDrag();
   if(g_count>=MaxSetups()){Status("Drawing limit reached; delete a drawing first.");return;}
   CloseEditor();g_armed=true;HoldScroll();Status("Press, drag and release on the chart. Esc cancels.");
  }
void CancelDrag()
  {
   if(g_toolbar_drag){g_toolbar_drag=false;g_toolbar_moved=false;SaveLayout();}
   if(g_created>=0 && g_created<g_count){g_count--;g_selected=g_previous_selection;}
   else if(g_drag!=0 && g_selected>=0 && g_selected<g_count)g_sets[g_selected]=g_drag_backup;
   g_created=-1;g_drag=0;g_armed=false;ReleaseScroll();g_dirty=true;g_ui_dirty=true;
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
      if(!Snap(x,y,(ENUM_TIMEFRAMES)_Period,t,p)){Status("Choose a point inside the main chart window.");return;}
      if(g_count>=MaxSetups())return;
      g_previous_selection=g_selected;g_created=g_count;g_selected=g_count;g_count++;
      NewSetup(g_sets[g_selected]);g_sets[g_selected].ta=t;g_sets[g_selected].tb=t;g_sets[g_selected].pa=p;g_sets[g_selected].pb=p;
      g_sets[g_selected].left=t;g_sets[g_selected].right=t+(datetime)PeriodSeconds();g_drag=1;
      g_drag_x=x;g_drag_y=y;g_dirty=true;return;
     }
   if(g_selected>=0)
     {
      int handle=HitHandle(g_sets[g_selected],x,y);
      if(handle>0 && Point(x,y,t,p))
        {
         g_drag=handle;g_drag_backup=g_sets[g_selected];g_drag_time=t;g_drag_price=p;g_drag_x=x;g_drag_y=y;HoldScroll();return;
        }
     }
   int hit=-1;
   if(g_selected>=0 && HitSetup(g_sets[g_selected],x,y))hit=g_selected;
   else for(int i=g_count-1;i>=0;i--)if(HitSetup(g_sets[i],x,y)){hit=i;break;}
   ulong now=GetTickCount64();
   bool twice=hit>=0 && hit==g_last_hit && now-g_last_down<400;
   g_selected=hit;g_last_hit=hit;g_last_down=now;g_dirty=true;g_ui_dirty=true;
   if(twice)OpenEditor();
  }
void MoveMouse(const int x,const int y)
  {
   if(g_toolbar_drag)
     {
      int tx=Lim(x-g_toolbar_dx,0,(int)MathMax(0,g_width-U(FP_TOOLBAR_WIDTH))),ty=Lim(y-g_toolbar_dy,0,(int)MathMax(0,g_height-U(FP_TOOLBAR_HEIGHT)));
      int dx=tx-g_toolbar_x,dy=ty-g_toolbar_y;
      if(dx!=0 || dy!=0)
        {
         g_toolbar_moved=true;
         string keys[]={"Grip","Close","New","Prev","Next","Properties","Duplicate","Delete","Hide"};
         for(int i=0;i<ArraySize(keys);i++)
           {string n=UIS("T."+keys[i]);if(ObjectFind(0,n)<0)continue;ObjectSetInteger(0,n,OBJPROP_XDISTANCE,ObjectGetInteger(0,n,OBJPROP_XDISTANCE)+dx);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,ObjectGetInteger(0,n,OBJPROP_YDISTANCE)+dy);}
         g_toolbar_x=tx;g_toolbar_y=ty;g_toolbar_lx=tx/g_scale;g_toolbar_ly=ty/g_scale;ChartRedraw();
        }
      return;
     }
   if(g_drag==0)return;
   if(g_selected<0 || g_selected>=g_count){CancelDrag();return;}
   datetime t=0;double p=0;
   if(g_drag<=3)
     {
      if(!Snap(x,y,g_sets[g_selected].source_tf,t,p))return;
      if(g_drag==2){g_sets[g_selected].ta=t;g_sets[g_selected].pa=p;}
      else {g_sets[g_selected].tb=t;g_sets[g_selected].pb=p;}
      if(g_drag==1)
        {
         g_sets[g_selected].left=(datetime)MathMin((long)g_sets[g_selected].ta,(long)t);
         g_sets[g_selected].right=(datetime)MathMax((long)g_sets[g_selected].ta,(long)t);
         if(g_sets[g_selected].right==g_sets[g_selected].left)g_sets[g_selected].right+=(datetime)PeriodSeconds(g_sets[g_selected].source_tf);
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
         g_sets[g_selected].pa=g_drag_backup.pa+dp;g_sets[g_selected].pb=g_drag_backup.pb+dp;
         g_sets[g_selected].left=(datetime)((long)g_drag_backup.left+dt);g_sets[g_selected].right=(datetime)((long)g_drag_backup.right+dt);
        }
     }
   g_dirty=true;
  }
void EndMouse(const int x,const int y)
  {
   if(g_toolbar_drag)
     {MoveMouse(x,y);g_toolbar_drag=false;ReleaseScroll();if(g_toolbar_moved){g_ignore_toolbar_click_until=GetTickCount64()+180;SaveLayout();}g_toolbar_moved=false;return;}
   if(g_drag==0)return;
   if(g_selected<0 || g_selected>=g_count){CancelDrag();return;}
   MoveMouse(x,y);
   if(g_sets[g_selected].pa==g_sets[g_selected].pb || (g_drag==1 && MathAbs(x-g_drag_x)+MathAbs(y-g_drag_y)<4))
     {CancelDrag();Status("Drawing canceled: drag between two different prices.");return;}
   bool created=g_drag==1;
   g_created=-1;g_drag=0;g_armed=false;ReleaseScroll();g_ui_dirty=true;g_dirty=true;
   if(!Save())
     {
      if(created){g_count--;g_selected=g_previous_selection;}
      else g_sets[g_selected]=g_drag_backup;
      g_dirty=true;return;
     }
   if(!created || RememberConfig(g_sets[g_selected]))Status("Drawings saved. Select a line; double-click a line for properties.");
  }
void RemoveSelected()
  {
   if(g_drag!=0)CancelDrag();
   if(g_selected<0 || g_selected>=g_count)return;
   int selected=g_selected;FPSetup removed=g_sets[selected];
   CloseEditor();for(int i=selected;i<g_count-1;i++)g_sets[i]=g_sets[i+1];
   g_count--;g_selected=-1;
   if(!Save())
     {for(int i=g_count;i>selected;i--)g_sets[i]=g_sets[i-1];g_sets[selected]=removed;g_count++;g_selected=selected;}
   g_dirty=true;g_ui_dirty=true;
  }

// A chart/object click is a second release signal if the mouse-move release
// was lost (for example when releasing outside the chart and returning).
void FinishPointer(const int x,const int y)
  {
   g_prev_down=false;g_picker_drag=0;
   g_ui_defer_until=GetTickCount64()+32;
   if(g_drag!=0 && HitUI(x,y))CancelDrag();else EndMouse(x,y);
  }
void HandlePointer(const int x,const int y,const bool down)
  {
   bool was_down=g_prev_down;
   PickerMouse(x,y,down,was_down);
   if(down && !was_down)BeginMouse(x,y);
   else if(down && (g_drag!=0 || g_toolbar_drag))MoveMouse(x,y);
   else if(down)g_view_probe=true;
   else if(was_down || g_drag!=0 || g_toolbar_drag)FinishPointer(x,y);
   if((down || was_down) && g_drag==0 && !g_toolbar_drag && !g_editor && g_popup==0 && !HitUI(x,y))
     {g_fast_view_until=GetTickCount64()+150;g_view_probe=true;}
   g_prev_down=down;
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
   if(StringFind(name,UIS("T."))==0 && GetTickCount64()<g_ignore_toolbar_click_until)return;
   if((ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
   if(name==UIS("T.Close")){DetachTool();return;}
   // Explicit toolbar commands recover from a stale drawing/dragging state.
   if(StringFind(name,UIS("T."))==0 && (g_drag!=0 || g_toolbar_drag || g_armed))CancelDrag();
   if(StringFind(name,Obj("R."))==0)
     {
      if(name==Obj("R.Name"))return;
      HarvestPresetName();
      if(name==Obj("R.Cancel")){ClosePopup();return;}
      if(name==Obj("R.Action")){PresetAction();return;}
      if(name==Obj("R.Prev")){g_preset_page=(int)MathMax(0,g_preset_page-1);PresetBrowser(g_preset_save,false);return;}
      if(name==Obj("R.Next")){g_preset_page=(int)MathMin((int)MathMax(0,(g_preset_count-1)/7),g_preset_page+1);PresetBrowser(g_preset_save,false);return;}
      if(StringFind(name,Obj("R.Item"))==0)
        {int i=(int)StringToInteger(StringSubstr(name,StringLen(Obj("R.Item"))));if(i>=0 && i<g_preset_count){g_preset_name=g_preset_names[i];ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,g_preset_name);}return;}
      return;
     }
   if(g_popup==4)return;
   if(StringFind(name,Obj("D."))==0)
     {
      int choice=(int)StringToInteger(StringSubstr(name,StringLen(Obj("D."))));
      if(g_editor && g_popup_row>=0 && g_popup_row<g_edit.count && choice>=0 && choice<5)
        {if(g_popup==1)g_edit.levels[g_popup_row].style=choice;else if(g_popup==2)g_edit.levels[g_popup_row].width=choice+1;}
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
   if(key=="T.Prev" || key=="T.Next")
     {if(g_count>0){CloseEditor();g_selected=(g_selected+(key=="T.Next"?1:-1)+g_count)%g_count;g_ui_dirty=true;g_dirty=true;}return;}
   if(!g_editor || StringFind(key,"E.")!=0)return;
   key=StringSubstr(key,2);
   if((ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_BUTTON && key!="Cancel")
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
   if(StringFind(key,"Color")==0){Palette((int)StringToInteger(StringSubstr(key,5)));return;}
   if(key=="FillTop"){Palette(-2);return;}if(key=="FillBottom"){Palette(-3);return;}if(key=="BaseColor"){Palette(-4);return;}
   if(StringFind(key,"On")==0 && key!="OnlySource")
     {int i=(int)StringToInteger(StringSubstr(key,2));if(i>=0 && i<g_edit.count)g_edit.levels[i].enabled=!g_edit.levels[i].enabled;}
   else if(StringFind(key,"Remove")==0)
     {int i=(int)StringToInteger(StringSubstr(key,6));if(i>=0 && i<g_edit.count){for(int k=i;k<g_edit.count-1;k++)g_edit.levels[k]=g_edit.levels[k+1];g_edit.count--;g_page=Lim(g_page,0,(int)MathMax(0,(g_edit.count-1)/g_rows));}}
   else if(key=="Add")
     {if(g_edit.count<FP_MAX_LEVELS){int i=g_edit.count++;g_edit.levels[i].enabled=true;g_edit.levels[i].value=.75;g_edit.levels[i].description="%%  (%$)";g_edit.levels[i].style=0;g_edit.levels[i].width=1;g_edit.levels[i].ink=InpDefaultColor;g_page=i/g_rows;}}
   else if(key=="Defaults"){Defaults(g_edit);g_page=0;}
   else if(key=="PageBack")g_page=(int)MathMax(0,g_page-1);
   else if(key=="PageNext")g_page=(int)MathMin((int)MathMax(0,(g_edit.count-1)/g_rows),g_page+1);
   else if(key=="Labels")g_edit.labels=!g_edit.labels;
   else if(key=="Diagonal")g_edit.diagonal=!g_edit.diagonal;
   else if(key=="Lock")g_edit.anchors_locked=!g_edit.anchors_locked;
   else if(key=="RayL")g_edit.ray_left=!g_edit.ray_left;
   else if(key=="RayR")g_edit.ray_right=!g_edit.ray_right;
   else if(key=="Fill")g_edit.fill=!g_edit.fill;
   else if(key=="Gradient")g_edit.gradient=!g_edit.gradient;
   else if(key=="FillRays")g_edit.fill_rays=!g_edit.fill_rays;
   else if(key=="AllLower"){g_edit.visible_mask=Allowed(g_edit.source_tf);g_edit.visibility_mode=1;}
   else if(key=="OnlySource"){g_edit.visible_mask=(long)1<<TFIndex(g_edit.source_tf);g_edit.visibility_mode=2;}
   else if(StringFind(key,"TF")==0)
     {int i=(int)StringToInteger(StringSubstr(key,2));if(i>=0 && i<=TFIndex(g_edit.source_tf)){g_edit.visible_mask^=((long)1<<i);g_edit.visibility_mode=0;}}
   else return; // Clicking an edit field must not rebuild and destroy its focus.
   g_ui_dirty=true;g_dirty=true;
  }
void EndEdit(const string name)
  {
   if(!g_editor || StringFind(name,UIS("E."))!=0 || ObjectFind(0,name)<0)return;
   string key=StringSubstr(name,StringLen(UIS("E."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   bool accepted=true;
   if(key=="Name")g_edit.name=StringSubstr(text,0,120);
   else if(key=="Description")g_edit.description=StringSubstr(text,0,240);
   else if(StringFind(key,"Text")==0)
     {int i=(int)StringToInteger(StringSubstr(key,4));if(i>=0 && i<g_edit.count)g_edit.levels[i].description=StringSubstr(text,0,160);}
   else if(StringFind(key,"Value")==0)
     {int i=(int)StringToInteger(StringSubstr(key,5));double v=StringToDouble(text);if(i>=0 && i<g_edit.count && Numeric(text) && MathIsValidNumber(v) && MathAbs(v)<=1000)g_edit.levels[i].value=v;else accepted=false;}
   else if(key=="Opacity")
     {if(Numeric(text))g_edit.opacity=Lim((int)StringToInteger(text),0,100);else accepted=false;}
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
   // No mutation of the object collection while enumerating it.
   int total=ObjectsTotal(0,0,-1);
   for(int i=0;i<total;i++)
     {
      string n=ObjectName(0,i,0,-1);
      if(StringFind(n,UIS("E."))==0 && (ENUM_OBJECT)ObjectGetInteger(0,n,OBJPROP_TYPE)==OBJ_EDIT)EndEdit(n);
     }
   return !g_edit_error;
  }

int OnInit()
  {
   if(!ParseHotkey(InpPanelHotkey,g_panel_key,g_panel_ctrl,g_panel_shift,g_panel_alt) || !ParseHotkey(InpDuplicateHotkey,g_duplicate_key,g_duplicate_ctrl,g_duplicate_shift,g_duplicate_alt) || SameShortcut())
     {Print("Fibonacci Pro: use two different shortcuts, e.g. Ctrl+Shift+H and Ctrl+Shift+D (letters, digits or F1..F12).");return INIT_PARAMETERS_INCORRECT;}
   g_prefix="FP5."+SafeName(InpWorkspace)+".";
   if(ObjectFind(0,Obj("Alive"))>=0){Print("Fibonacci Pro: this workspace is already attached. Use a different InpWorkspace.");return INIT_FAILED;}
   if(!ObjectCreate(0,Obj("Alive"),OBJ_LABEL,0,0,0))return INIT_FAILED;
   ObjectSetInteger(0,Obj("Alive"),OBJPROP_HIDDEN,true);ObjectSetString(0,Obj("Alive"),OBJPROP_TEXT,"");
   string key=StringLen(InpStorageKey)>0?SafeName(InpStorageKey):IntegerToString(ChartID());
   FolderCreate("FibonacciPro");
   FolderCreate("FibonacciPro\\Presets");
   g_last_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".last.fpp";
   g_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(_Symbol)+"_"+SafeName(InpWorkspace)+"_"+key+".bin";
   g_file_lock=FileOpen(g_store+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_file_lock==INVALID_HANDLE)
     {Print("Fibonacci Pro: snapshot is in use on another chart, or its folder is not writable. Choose a unique storage key.");ObjectDelete(0,Obj("Alive"));g_store="";return INIT_FAILED;}
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
   g_status="Panel: "+InpPanelHotkey+" | Duplicate: "+InpDuplicateHotkey;
   g_old_mouse=(bool)ChartGetInteger(0,CHART_EVENT_MOUSE_MOVE);ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   if(!EventSetMillisecondTimer(Lim(InpFrameMilliseconds,16,100)))return INIT_FAILED;
   ViewChanged();g_ui_dirty=true;g_dirty=true;
   g_shortname="Fibonacci Pro ["+InpWorkspace+"]";
   IndicatorSetString(INDICATOR_SHORTNAME,g_shortname);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   // An INIT_FAILED duplicate instance must not delete another instance's objects.
   if(g_store=="")return;
   if(g_drag!=0 || g_toolbar_drag)CancelDrag();ReleaseScroll();
   // Last committed state only; unapplied dialog edits are deliberately discarded.
   ClosePopup();g_fill_canvas.Destroy();g_line_canvas.Destroy();DeletePrefix(g_prefix);
   if(g_file_lock!=INVALID_HANDLE){FileClose(g_file_lock);g_file_lock=INVALID_HANDLE;}
   bool other_instance=false;
   for(int i=ObjectsTotal(0)-1;i>=0;i--){string n=ObjectName(0,i);if(StringFind(n,"FP5.")==0 && StringFind(n,".Alive")>=0){other_instance=true;break;}}
   if(!g_old_mouse && !other_instance)ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);ChartRedraw();
  }
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
  {g_view_probe=true;if(rates_total!=prev_calculated)g_dirty=true;return rates_total;}
// Shared by mouse/chart events and the timer: no extra timer wait after an event.
void RefreshFrame(const bool probe=false)
  {
   if(g_detaching)return;
   if(probe)g_view_probe=true;
   ulong now=GetTickCount64();
   // Coalesce high-frequency events; leave dirty/probe flags set for the next frame.
   if(now-g_last_frame<(ulong)Lim(InpFrameMilliseconds,16,100))return;
   g_last_frame=now;
   // MT5 can deliver a mouse event before its chart projection has updated.
   // Poll each frame during chart panning and for 150 ms after the last pan event.
   if(g_view_probe || now<g_fast_view_until || now-g_last_view>=200)
     {if(ViewChanged())g_dirty=true;g_last_view=now;g_view_probe=false;}
   bool changed=false;
   if(g_dirty && now>=g_render_retry_after){Render();changed=true;}
   // Leave a short grace period for queued native OBJECT_CLICK events.
   if(g_ui_dirty && !g_prev_down && !g_toolbar_drag && g_drag==0 && now>=g_ui_defer_until)
     {ClosePopup();BuildUI();changed=true;}
   if(changed)ChartRedraw();
  }
void OnTimer(){RefreshFrame();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(g_detaching)return;
   if(id==CHARTEVENT_CHART_CHANGE){g_fast_view_until=GetTickCount64()+150;RefreshFrame(true);return;}
   if(id==CHARTEVENT_OBJECT_ENDEDIT){if(sparam==Obj("R.Name"))HarvestPresetName();else if(g_popup==0)EndEdit(sparam);return;}
   if(id==CHARTEVENT_CLICK)
     {if(g_prev_down || g_drag!=0 || g_toolbar_drag)FinishPointer((int)lparam,(int)dparam);return;}
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(g_prev_down || g_drag!=0 || g_toolbar_drag)FinishPointer((int)lparam,(int)dparam);
      if(StringFind(sparam,g_prefix)==0)Click(sparam);
      else if(!g_editor && g_drag==0 && g_selected>=0){g_selected=-1;g_dirty=true;g_ui_dirty=true;}
      return;
     }
   if(id==CHARTEVENT_KEYUP)
     {if((int)lparam==g_panel_key)g_panel_key_held=false;if((int)lparam==g_duplicate_key)g_duplicate_key_held=false;return;}
   if(id==CHARTEVENT_KEYDOWN)
     {
      int key=(int)lparam;
      if(key==27){if(g_popup!=0)ClosePopup();else if(g_editor)CloseEditor();else CancelDrag();return;}
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
