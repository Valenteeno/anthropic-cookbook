// Fibonacci Pro 1.71 -- custom drawing indicator for MetaTrader 5.
// No trading functions, DLLs, network access or external fonts/assets.
// Install in MQL5/Indicators, compile with the current MetaEditor 5.
#property copyright "Custom implementation for the user"
#property version   "1.71"
#property description "Fibonacci drawings typed and numbered automatically, ICT price points, a lot size & risk crosshair, drawings list, and ICT sessions, killzones & macros with alerts."
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
input color  InpColorMN=C'255,102,184';  // Monthly drawings
input color  InpColorW1=C'255,255,25';   // Weekly drawings
input color  InpColorD1=C'25,255,255';   // Daily drawings
input color  InpColorH4=C'255,136,0';    // H4 to H12 drawings
input color  InpColorH1=C'140,140,255';  // H1 to H3 drawings
input color  InpColorM15=C'230,195,126'; // M15 to M30 drawings
input color  InpColorM5=C'102,204,255';  // M5 to M12 drawings
input color  InpColorM1=C'140,140,140';  // M1 to M4 drawings
input int    InpWidthHigh=2;             // Line width of MN, W1 and D1 drawings (1..5)
input int    InpWidthLow=1;              // Line width below D1 (1..5)
input int    InpMaximumSetups=1000;    // 1..1000 drawings per workspace
input bool   InpHoverCandleInfo=true;  // Hover a candle to show its OHLC
input bool   InpHoverFibInfo=true;     // Hover a Fib level to show its details
input string InpPanelHotkey="Ctrl+Shift+H";     // Hide/show the full tool interface
input string InpDuplicateHotkey="Ctrl+Shift+D"; // Duplicate highlighted custom Fib
input string InpZonesHotkey="Ctrl+Shift+K";     // Show/hide sessions, killzones & macros
input string InpRiskHotkey="Ctrl+Shift+R";      // Lot size & risk: new measurement
input string InpPointsHotkey="Ctrl+Shift+L";    // Show/hide price points

#define FP_TOOLBAR_WIDTH 466
#define FP_TOOLBAR_HEIGHT 49
#define FP_PANEL_WIDTH 488
#define FP_LIST_WIDTH 548
#define FP_VERSION "1.71"
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
   int kind;                       // Detected type (FPK_*), FPK_NONE when nothing matched
   int dir;                        // 0 none, 1 bullish, 2 bearish
   bool used,used_ray;             // Marked as used; whether it was rayed right before
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

// ---- drawing types (1.65): detected from the anchors when a drawing is created
#define FPK_NONE 0
#define FPK_FVG 1
#define FPK_VI 2
#define FPK_UFVG 3
#define FPK_SPB 4
#define FPK_OB 5
#define FPK_PW 6
#define FPK_DW 7
#define FPK_KH 8
#define FPK_KL 9
#define FPK_KR 10
#define FPK_COUNT 11
#define FP_BUILTIN_COUNT 11
#define FP_USED_ALPHA 102
#define FP_BUILTIN_MARKER "FibonacciPro\\Presets\\builtins.v1"

// ---- lot size & risk (1.66): a one-off crosshair measurement sized from the account risk
#define FPR_MAGIC 1179668841
#define FPR_END 1179668849
#define FPR_SCHEMA 1
#define FPR_MAX_SYMS 200
#define FPR_MAX_TP 8
#define FPR_PANEL_HEIGHT 396
#define FPR_LOSS C'255,82,82'      // stop line and loss area
#define FPR_PROFIT C'38,198,118'   // target lines and profit area
// Per-account risk settings, plus a commission and an optional value of your own per symbol.
struct FPRiskSym
  {
   string symbol;
   double commission;          // account currency per 1.00 lot, round turn (open + close)
   double value;               // your own value: account currency per 1.0 price move per 1.00 lot (0: none)
  };
struct FPRiskConfig
  {
   int mode;                   // 0 fixed amount, 1 % of balance, 2 % of equity, 3 % of a fixed base
   double amount,percent,base;
   int entry;                  // 0 market (live bid/ask), 1 limit/pending at a chosen price
   string targets;             // R multiples a new measurement starts with, e.g. "2" or "1 2 3"
   string add_r;               // R multiples the +TP button adds
   int count;
   FPRiskSym syms[FPR_MAX_SYMS];
  };
// The measurement on the chart. It is never saved: Esc, the bar's close button or a new
// measurement removes it.
struct FPRisk
  {
   bool armed;                 // crosshair shown, the measurement is being made
   bool active;                // a box is on the chart
   int stage;                  // limit entry: 1 once the entry is placed (the stop follows the pointer)
   bool market;                // entry at the live ask (long) / bid (short)
   datetime t0;                // where the box starts
   double entry,stop;          // entry: limit entry price
   int ntp;
   double tp[FPR_MAX_TP];      // price of a dragged target
   double tp_r[FPR_MAX_TP];    // R multiple of a target that follows the stop
   bool tp_fixed[FPR_MAX_TP];  // true: at tp_r; false: dragged to tp
  };
// What the chart shows for the measurement, computed once per frame from live prices.
struct FPRiskView
  {
   int side;                   // 1 long, -1 short, 0 invalid (stop inside the spread or at the entry)
   double entry,stop,dist;     // dist: price distance entry to stop
   double risk;                // wanted loss at the stop, account currency
   double commission;          // per 1.00 lot, round turn
   double lots,per_lot,actual; // per_lot: loss of 1.00 lot incl. commission; actual: loss of `lots`
   double min_risk;            // loss of the minimum volume
   int flag;                   // FPRiskLots: 0 ok, 1 below the minimum volume, 2 capped, -1 no size
   int ntp;
   double tp[FPR_MAX_TP],tp_r[FPR_MAX_TP];
   string why;                 // why there is no size
  };
// A price tag at the right edge of the chart, pushed clear of its neighbours.
struct FPRTag
  {int y,pos;string text;color bg,ink;};
struct FPRiskSymInfo
  {
   string profit_ccy,account_ccy;
   double contract,tick_size,point,vmin,vmax,vstep;
   int digits,calc_mode;
   bool fx;                    // distances in pips, values per pip
  };
// Value of a 1.0 price move on 1.00 lot in the account currency, by method.
struct FPRiskValue
  {
   int source;                 // 0 none, 1 your own, 2 calibration, 3 contract and tick value agree, 4 contract only, 5 tick value only
   double value;               // the value used (0: no size)
   double contract,tick,calib; // each method (0: unavailable)
   bool disagree,calib_stale;
  };

// CALIB_IO_BEGIN -- the same text is in Fibonacci_Pro_Calibrate.mq5 (the build checks it)
#define FPC_MAGIC 1179668851
#define FPC_END 1179668859
#define FPC_SCHEMA 1
#define FPC_MAX 2000
#define FPC_TOL 0.02
// One calibrated symbol: the money a 1.0 price move makes on 1.00 lot, from the terminal's
// own profit calculation (OrderCalcProfit), measured by the calibration script.
struct FPCalib
  {
   string symbol,profit_ccy,account_ccy;
   double value_profit;        // profit currency per 1.0 price move per 1.00 lot (0: no rate to convert)
   double value_account;       // the same in the account currency, at the rate of the calibration
   double contract,tick_size,tick_value;  // the symbol's properties then (a changed contract voids it)
   long time;                  // server time of the calibration
  };
string FPCSafe(string value)
  {
   string forbidden="\\/:*?\"<>|\r\n\t";
   for(int i=0;i<StringLen(forbidden);i++)StringReplace(value,StringSubstr(forbidden,i,1),"_");
   return StringSubstr(value,0,80);
  }
// One file per trade server: every account and chart on that server shares it.
string FPCFile(){return "FibonacciPro\\"+FPCSafe(AccountInfoString(ACCOUNT_SERVER))+".calib";}
void FPCWText(const int f,const string text)
  {FileWriteInteger(f,StringLen(text),INT_VALUE);if(StringLen(text)>0)FileWriteString(f,text,StringLen(text));}
bool FPCRText(const int f,string &text,const int maxlen)
  {int n=FileReadInteger(f,INT_VALUE);if(n<0 || n>maxlen)return false;if(n==0){text="";return true;}text=FileReadString(f,n);return StringLen(text)==n;}
// Number of records, or -1 when the file is missing or damaged (nothing is half-read).
int FPCLoad(const string filename,FPCalib &list[])
  {
   ArrayResize(list,0);
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return -1;
   int n=0;
   bool good=FileReadInteger(f,INT_VALUE)==FPC_MAGIC && FileReadInteger(f,INT_VALUE)==FPC_SCHEMA;
   if(good){n=FileReadInteger(f,INT_VALUE);good=n>=0 && n<=FPC_MAX;}
   if(good)ArrayResize(list,n);
   for(int i=0;good && i<n;i++)
     {
      good=FPCRText(f,list[i].symbol,64) && FPCRText(f,list[i].profit_ccy,16) && FPCRText(f,list[i].account_ccy,16);
      if(!good)break;
      list[i].value_profit=FileReadDouble(f);list[i].value_account=FileReadDouble(f);
      list[i].contract=FileReadDouble(f);list[i].tick_size=FileReadDouble(f);list[i].tick_value=FileReadDouble(f);
      list[i].time=FileReadLong(f);
      good=MathIsValidNumber(list[i].value_profit) && MathIsValidNumber(list[i].value_account) && list[i].value_profit>=0 && list[i].value_account>0
           && MathIsValidNumber(list[i].contract) && MathIsValidNumber(list[i].tick_size) && MathIsValidNumber(list[i].tick_value);
     }
   if(good)good=FileReadInteger(f,INT_VALUE)==FPC_END && FileTell(f)==FileSize(f);
   FileClose(f);
   if(!good){ArrayResize(list,0);return -1;}
   return n;
  }
// Written to a temporary file, verified by reading it back, then swapped in (old copy kept as .bak).
bool FPCSave(const string filename,FPCalib &list[],const int n)
  {
   string temporary=filename+".tmp";
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();
   FileWriteInteger(f,FPC_MAGIC,INT_VALUE);FileWriteInteger(f,FPC_SCHEMA,INT_VALUE);FileWriteInteger(f,n,INT_VALUE);
   for(int i=0;i<n;i++)
     {
      FPCWText(f,list[i].symbol);FPCWText(f,list[i].profit_ccy);FPCWText(f,list[i].account_ccy);
      FileWriteDouble(f,list[i].value_profit);FileWriteDouble(f,list[i].value_account);
      FileWriteDouble(f,list[i].contract);FileWriteDouble(f,list[i].tick_size);FileWriteDouble(f,list[i].tick_value);
      FileWriteLong(f,list[i].time);
     }
   FileWriteInteger(f,FPC_END,INT_VALUE);FileFlush(f);int error=GetLastError();FileClose(f);
   FPCalib check[];
   if(error!=0 || FPCLoad(temporary,check)!=n)return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }
int FPCFind(FPCalib &list[],const int n,const string symbol)
  {for(int i=0;i<n;i++)if(list[i].symbol==symbol)return i;return -1;}
// Calculation modes whose profit is (close - open) x contract size x lots, in the profit currency.
bool FPCContractMode(const long mode)
  {
   return mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE || mode==SYMBOL_CALC_MODE_CFD
          || mode==SYMBOL_CALC_MODE_CFDINDEX || mode==SYMBOL_CALC_MODE_CFDLEVERAGE
          || mode==SYMBOL_CALC_MODE_EXCH_STOCKS || mode==SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX;
  }
// A symbol quoting one currency in the other: Market Watch first, forex symbols preferred.
// inverse: the symbol is `to` per `from`. A symbol found outside Market Watch is added to
// it, because the terminal only streams quotes for selected symbols.
bool FPCFindConv(const string from,const string to,string &sym,bool &inverse)
  {
   int best=-1;sym="";inverse=false;
   for(int pass=0;pass<2 && best<0;pass++)
     {
      bool selected=pass==0;
      int n=SymbolsTotal(selected);
      for(int i=0;i<n;i++)
        {
         string s=SymbolName(i,selected);
         string b=SymbolInfoString(s,SYMBOL_CURRENCY_BASE),p=SymbolInfoString(s,SYMBOL_CURRENCY_PROFIT);
         bool direct=b==from && p==to,inv=b==to && p==from;
         if(!direct && !inv)continue;
         long mode=SymbolInfoInteger(s,SYMBOL_TRADE_CALC_MODE);
         int score=(mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)?2:1;
         if(SymbolInfoDouble(s,SYMBOL_BID)>0)score+=2;
         if(score>best){best=score;sym=s;inverse=inv;}
        }
     }
   if(best<0)return false;
   if(SymbolInfoInteger(sym,SYMBOL_SELECT)==0)SymbolSelect(sym,true);
   return true;
  }
// Units of `to` per unit of `from` (0: no symbol or no quote). key/sym/inv cache the search.
double FPCConv(const string from,const string to,string &key,string &sym,bool &inv)
  {
   if(from=="" || to=="")return 0;
   if(from==to)return 1.0;
   if(key!=from+">"+to){key=from+">"+to;FPCFindConv(from,to,sym,inv);}
   if(sym=="")return 0;
   double bid=SymbolInfoDouble(sym,SYMBOL_BID),ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   if(inv)return ask>0?1.0/ask:0;
   return bid>0?bid:0;
  }
// Contract method: contract size x conversion to the account currency (0: not this kind of symbol).
double FPCContractValue(const string sym,const string acc,string &key,string &csym,bool &inv)
  {
   if(!FPCContractMode(SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE)))return 0;
   double contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   if(!(contract>0))return 0;
   double conv=FPCConv(SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT),acc,key,csym,inv);
   return conv>0?contract*conv:0;
  }
// Tick-value method: the broker's tick value for a losing position / tick size.
double FPCTickValue(const string sym)
  {
   double size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE),value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(!(value>0))value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   return size>0 && value>0?value/size:0;
  }
// CALIB_IO_END

// ---- price points (1.67-1.69): session, gap, opening-range, FPFVG/FPOB and period levels
#define FPP_MAX 64
#define FPP_GROUPS 6
#define FPP_MAGIC 1179668861
#define FPP_END 1179668869
#define FPP_SCHEMA 3
#define FPP_FLAGS_MAGIC 1179668871
#define FPP_FLAGS_END 1179668879
#define FPP_FLAGS2_MAGIC 1179668881       // 1.69: flags per line, and ends set by hand
#define FPP_FLAGS2_END 1179668889
#define FPP_FLAGS_MAX 4000
#define FPP_PANEL_WIDTH 700
#define FPP_BUILTIN_ICT "ICT price points [built-in]"
#define FPP_BUILTIN_OFF "All off [built-in]"
// Row kinds.
#define FPPK_WINDOW 0              // high/low of a time window (sessions, pre-sessions, opening ranges)
#define FPPK_OPEN 1                // opening price at a time (midnight open)
#define FPPK_GAP 2                 // close-to-open gap: sub 0 ORG, 1 NDOG, 2 NWOG
#define FPPK_FVG 3                 // first M1 fair value gap of a window
#define FPPK_OB 4                  // first M1 order block before a break of structure in a window
#define FPPK_PERIOD 5              // open/high/low/close of a period: sub 0 day, 1 week, 2 month
// Parts a row draws (bits of FPPoint.parts). For FVG and OB rows, H and L are the top and bottom edges.
#define FPPP_H 1
#define FPPP_L 2
#define FPPP_CE 4
#define FPPP_BOX 8
#define FPPP_O 16
#define FPPP_C 32
#define FPPP_Q 64                  // quadrants: 25% and 75% of the range
#define FPPP_E 128                 // octants: 12.5%, 37.5%, 62.5% and 87.5%
// Lines of an occurrence, by index: 0 high, 1 low, 2 CE, 3 box, 4 open, 5 close,
// 6-7 the quadrants, 8-11 the octants (each shown by the bit FPPBitOf gives).
#define FPP_PARTS 12
// One row of the price points table. Times are minutes after midnight, New York.
struct FPPoint
  {
   bool enabled;
   string name,hname,lname;    // row name; high/open line name; low/close line name
   string sname;               // name on the chart (labels), empty: the row name
   int kind,sub,group;
   int start,end;              // window; open time (start); gap: close candle (start) and open time (end)
   int len,swing,look;         // FVG/OB: window minutes, swing width (bars), BOS lookahead (minutes)
   int parts;                  // FPPP_* bits drawn
   int style;                  // -1 by role, 0..4 one line style for every part
   int width;
   color ink;
   int label;                  // 0 as set in Visualization, 1..4 = label modes 0..3
   int ends;                   // 0 as set in Parameters, 1 at the take, 2 run to the right edge, 3 end of that day, 4 end of that week
   int sample;                 // 0 every trading day, 1 Mondays only
   int bold;                   // label weight: 0 as set in Visualization, 1 bold, 2 regular
   bool ray,alert;             // ray back by default; alert when a level of this row is taken
   uint uid;                   // stable identity (hidden/rayed occurrences are stored by it)
  };
struct FPPointConfig
  {
   bool enabled;
   bool group_on[FPP_GROUPS];
   int group_tf[FPP_GROUPS];   // highest timeframe index each group is drawn on
   int days_back,weeks_back,months_back;
   bool end_taken;             // lines end where price takes them
   int taken_end;              // ... at the take (0), at the end of that trading day (1) or of that week (2)
   int taken_show;             // taken levels: 0 dim, 1 hide, 2 keep
   int week_open;              // 0 first candle after the weekend (Sunday if the broker has one), 1 Monday's first candle
   int label_mode;             // 0 name, 1 name + day, 2 name + price, 3 off
   int label_size;
   bool label_bold;
   bool merge,pin_left,offscreen,hover;
   bool fill;
   int opacity;                // zone fill opacity 0..100
   int tint;                   // 0 OB lighter, FVG darker; 1 one shade
   bool range_fill;            // shade the range of window rows that draw their box
   bool alert_sound,alert_push;
   int count;
   FPPoint rows[FPP_MAX];
  };
// One drawn instance of a row: a trading day, a week or a month.
struct FPPOcc
  {
   int row,state,age;          // state: 0 unread, 1 has data, 2 none (holiday, no pattern), 3 waiting/loading
   uint uid,sig;               // row identity; what the row's window depends on (FPPRowSig)
   long key;                   // trading day; Monday's trading day for weekly rows; y*12+month-1 for months
   datetime ts,te;             // window (server time); gaps: close candle and open time
   datetime formed;            // levels final from here: taken scans start at this bar
   bool live,future;
   double hi,lo,op,cl;         // high/low (FVG/OB/gap: top/bottom), open, close
   datetime th,tl,to,tc;       // candle of the high, low, open and close
   int dir;                    // gap/FVG/OB: 1 up/bullish, -1 down/bearish, 0 flat
   datetime tk[FPP_PARTS];     // candle that took each part, 0 = not taken
   bool away[FPP_PARTS];       // price has left the level since it formed
   datetime scan_to;           // taken scan done up to here (0 = not started)
   int flags;                  // for the whole occurrence (1.67, 1.68): 1 ray back, 2 no ray back, 4 hidden, 8 ray forward
   int pflags[FPP_PARTS];      // the same per line (a gap, FVG or OB: per zone, at index 3)
   datetime pend[FPP_PARTS];   // end set by dragging the line's (zone's) right end, 0 = none
  };
// Stored per chart: price points rayed, hidden or extended by the user. part -1: the
// whole occurrence (as 1.67 and 1.68 stored it), otherwise a line, or index 3 for a zone.
struct FPPFlag
  {uint uid;long key;int part;int flags;datetime end;};
// Screen data of one drawn line, box and label (rebuilt every frame, reused by hover).
struct FPPLine
  {int occ,part,x0,x1,y,style,width;color ink;uchar alpha;bool taken,sel;};
struct FPPBox
  {int occ,x0,x1,y0,y1;color ink;uchar alpha;bool zone;};
struct FPPLabel
  {int x,y,w,h,line;string text;color ink;uchar alpha;bool bold;};
struct FPPOff
  {int occ,part,y;};

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
bool g_lvdrag=false,g_level_desc=false;
int g_lvdrag_from=-1,g_lvdrag_to=-1;
ulong g_ignore_editor_click_until=0,g_restore_confirm_until=0;
// Lot size & risk
FPRiskConfig g_rcfg,g_redit;
FPRisk g_risk,g_risk_backup;
FPRiskView g_rview;
FPRiskSymInfo g_rsym;
FPRiskValue g_rval;
FPCalib g_rcal;
FPRTag g_rtags[FPR_MAX_TP+2];
bool g_reditor=false,g_risk_key_held=false,g_rcal_found=false,g_rcal_checked=false,g_rstore_found=false;
bool g_rdrag_moved=false,g_rcreating=false,g_rgok=false,g_rconv_inv=false,g_rintro=false;
int g_risk_key=82;
bool g_risk_ctrl=true,g_risk_shift=true,g_risk_alt=false;
int g_rdrag=0,g_rdrag_px=0,g_rdrag_py=0,g_rpress_stage=0,g_rlast_hit=0,g_rtag_n=0;
int g_rgx0=0,g_rgye=0,g_rgys=0,g_rgfar=FP_OFF;
int g_rgty[FPR_MAX_TP];
ulong g_rtick=0,g_rinfo_tick=0,g_rlast_down=0;
double g_rlast_bid=0,g_rlast_ask=0,g_rlast_bal=0,g_rlast_eq=0;
string g_rstore="",g_rconv_key="",g_rconv_sym="";
datetime g_rstore_mtime=0,g_rcal_mtime=0;
// Price points
FPPointConfig g_pcfg,g_pedit,g_pact;
bool g_peditor=false,g_pocc_dirty=true,g_preset_points=false,g_points_key_held=false,g_psort_desc=false;
int g_ptab=3,g_ppage=0,g_pfilter=-1,g_psort=0,g_pocc_n=0,g_pp_daykey=0,g_pp_mode=-1,g_pp_gmt=-99,g_pp_rr=0;
int g_ppline_n=0,g_ppbox_n=0,g_pplabel_n=0,g_ppfill_n=0,g_ppoff_n=0,g_pflag_n=0,g_ppopup_reopen=-1;
int g_points_key=76;
bool g_points_ctrl=true,g_points_shift=true,g_points_alt=false;
ulong g_pp_tick=0,g_pp_retry=0,g_pp_poll=0,g_ppfill_sig=0;
string g_pstore="",g_pflag_store="";
datetime g_pstore_mtime=0;
FPPOcc g_pocc[];
FPPLine g_ppline[];
FPPBox g_ppbox[];
FPPLabel g_pplabel[];
FPPOff g_ppoff[];
FPLayer g_ppfill[];
FPPFlag g_pflags[];
uint g_psel_uid=0;
long g_psel_key=0;
int g_psel=-1,g_psel_part=-1,g_psel_x=0,g_psel_y=0,g_pchip_x=0,g_pchip_y=0;
int g_pp_first_x=-1000000,g_pp_font=-1;   // x of the chart's first candle (ray back); label font in use (-1 unknown)
int g_pchip_w=206;                         // width of the selected price point's buttons
bool g_ppdrag=false,g_ppdrag_moved=false;  // dragging the selected price point's right end
int g_ppdrag_part=-1,g_ppdrag_px=0,g_ppdrag_flags=0;
datetime g_ppdrag_end=0;
// Settings shared with other terminals (1.70): one file in MetaTrader's Common folder.
#define FPS_MAGIC 1179668901
#define FPS_END 1179668909
#define FPS_SCHEMA 1
#define FPS_FILE "FibonacciPro\\FibonacciPro.settings"
#define FPS_MAX_ENTRIES 1000
#define FPS_MAX_BYTES 1048576
#define FPS_STYLES 1                        // drawing style and every preset
#define FPS_ZONES 2
#define FPS_POINTS 4
#define FPS_RISK 8
#define FPS_POPUP_W 520
#define FPS_POPUP_H 310
int g_share_parts=15;                       // what an import takes (FPS_* bits)
bool g_share_clock=true;                    // an import keeps this account's broker clock
ulong g_share_confirm_until=0;              // Import asks for a second click
string g_share_msg="";                      // the popup's last message
string g_fps_names[];                       // the shared file, as last read
int g_fps_start[];
int g_fps_size[];
uchar g_fps_data[];
int g_fps_n=0;
string g_fps_version="";
long g_fps_time=0;

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
   bool pr=g_panel_key==g_risk_key && g_panel_ctrl==g_risk_ctrl && g_panel_shift==g_risk_shift && g_panel_alt==g_risk_alt;
   bool dr=g_duplicate_key==g_risk_key && g_duplicate_ctrl==g_risk_ctrl && g_duplicate_shift==g_risk_shift && g_duplicate_alt==g_risk_alt;
   bool zr=g_zones_key==g_risk_key && g_zones_ctrl==g_risk_ctrl && g_zones_shift==g_risk_shift && g_zones_alt==g_risk_alt;
   bool pp=g_panel_key==g_points_key && g_panel_ctrl==g_points_ctrl && g_panel_shift==g_points_shift && g_panel_alt==g_points_alt;
   bool dp=g_duplicate_key==g_points_key && g_duplicate_ctrl==g_points_ctrl && g_duplicate_shift==g_points_shift && g_duplicate_alt==g_points_alt;
   bool zp=g_zones_key==g_points_key && g_zones_ctrl==g_points_ctrl && g_zones_shift==g_points_shift && g_zones_alt==g_points_alt;
   bool rp=g_risk_key==g_points_key && g_risk_ctrl==g_points_ctrl && g_risk_shift==g_points_shift && g_risk_alt==g_points_alt;
   return SameShortcut() || pz || dz || pr || dr || zr || pp || dp || zp || rp;
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
   FPClearLevels(s);
   s.uid=g_next_uid++;s.name="Fibo "+IntegerToString(s.uid);s.description="";
   s.ta=0;s.tb=0;s.pa=0;s.pb=0;s.left=0;s.right=0;
   s.source_tf=(ENUM_TIMEFRAMES)_Period;s.visible_mask=Allowed(s.source_tf);s.visibility_mode=1;
   s.ray_left=false;s.ray_right=false;s.anchors_locked=false;s.diagonal=true;s.labels=true;
   s.label_v=0;s.label_h=0;s.label_float=true;s.hline=false;
   s.kind=FPK_NONE;s.dir=0;s.used=false;s.used_ray=false;
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
   flags|=(s.used?131072:0)|(s.used_ray?262144:0)|(Lim(s.kind,0,FPK_COUNT-1)<<19)|(Lim(s.dir,0,2)<<23); // 1.65; older versions ignore these bits
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
   s.used=(flags&131072)!=0;s.used_ray=(flags&262144)!=0;s.kind=(flags>>19)&15;s.dir=(flags>>23)&3;
   if(s.kind>=FPK_COUNT)s.kind=FPK_NONE;
   if(s.dir>2)s.dir=0;
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
   FPClearLevels(candidate);
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
   if(g_reditor){Status("Close the Risk window first.");return;}
   if(g_peditor){Status("Close the Price points window first.");return;}
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
   if(!g_hidden && g_reditor && !HarvestRiskEdits())return;
   if(!g_hidden && g_peditor && !HarvestPointEdits())return;
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
   if(FPIsDefaultName(source))g_sets[slot].name=FPDefaultName(g_sets[slot]);   // "H1 FVG 3": the next number
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
   int x=g_toolbar_x+U(8),y=g_toolbar_y+U(FP_TOOLBAR_HEIGHT+2)+(RiskBarShown()?U(26):0);   // below the risk bar
   int w=(int)MathMin(MathMax(U(60),g_width-x-4),U(16)+StringLen(text)*U(6));
   UIBase(UIS("T.StatusBG"),OBJ_RECTANGLE_LABEL,x,y,w,U(20),"",clrLightYellow,clrBlack,95);
   UIBase(UIS("T.Status"),OBJ_LABEL,x+U(6),y+U(3),0,0,text,clrWhite,clrBlack,100);
   g_status_shown=true;
  }
void BuildToolbar()
  {
   int x=g_toolbar_x,y=g_toolbar_y;
   // No toolbar background object: the chart remains visible between controls.
   Label("T.Grip",":: Fibonacci Pro "+g_version,x+U(7),y+U(3),g_chart_fg);
   string title=g_selected>=0 && g_selected<g_count?g_sets[g_selected].name:"No selection";
   Tooltip("T.Grip",title+" | "+g_status+" | Drag title to move");
   Button("T.Close",Glyph(0xD7),x+U(FP_TOOLBAR_WIDTH-28),y+U(1),20,18);
   Tooltip("T.Close","Detach Fibonacci Pro from this chart (saved drawings retained)");
   UpdateZonesButton();
   UpdateRiskButton();
   UpdatePointsButton();
   UpdateShareButton();
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
   int value=g_peditor?g_pedit.opacity:(g_zeditor?g_zedit.opacity:g_edit.opacity);
   int tx=g_slider_x0+(int)MathRound((g_slider_x1-g_slider_x0)*value/100.0)-U(5);
   Box(g_peditor?"N.OpThumb":(g_zeditor?"Z.OpThumb":"E.OpThumb"),tx,g_slider_y0+U(3),10,20,clrDimGray);
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
      Check("E.Diagonal","Show anchor diagonal",g_edit.diagonal,x+U(12),cy,200);
      Check("E.Used","Used (stop extending)",g_edit.used,x+U(250),cy,220);
      Tooltip("E.Used","Stops the drawing at the first candle that traded into it and fades it. Untick to keep extending.");
      cy+=U(27);
      Check("E.Lock","Lock price-anchor handles",g_edit.anchors_locked,x+U(12),cy,240);cy+=U(27);
      Check("E.LineMode","Horizontal line mode (move by origin handle)",g_edit.hline,x+U(12),cy,330);cy+=U(30);
      Tooltip("E.LineMode","Shows one origin handle on the first enabled level; dragging it or the line snaps to OHLC and keeps the line horizontal");
      Button("E.BaseColor","Diagonal color",x+U(12),cy,130,22,g_edit.base_color);
     }
   if(g_tab==1)
     {
      int source=TFIndex(g_edit.source_tf);
      Label("E.SrcTF","Drawn on "+(source>=0?g_tf_names[source]:"?")+" (fixed)   Type: "+FPKindLabel(g_edit)+(g_edit.dir==1?" "+Glyph(0x25B2):(g_edit.dir==2?" "+Glyph(0x25BC):"")),x+U(12),cy);cy+=U(29);
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
      Tooltip("E.Head2","%n shows the drawing's name, %% the level's percentage and %$ its price");
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
         Button("E.Drag"+n,Glyph(0x2261),x+U(456),ry,22);
         Tooltip("E.Drag"+n,"Drag up or down to move this level");
        }
      int fy=y+PanelHeight()-U(93);
      Button("E.Add","Add",x+U(12),fy,52);Button("E.Defaults","Defaults",x+U(66),fy,70);
      Button("E.Sort","Sort "+Glyph(g_level_desc?0x25BC:0x25B2),x+U(138),fy,64);
      Tooltip("E.Sort",g_level_desc?"Sort the levels from high to low":"Sort the levels from low to high");
      Button("E.PageBack","<",x+U(206),fy,26);Button("E.PageNext",">",x+U(234),fy,26);
      Button("E.AllWidth","All",x+U(cols[4]),fy,46);
      Tooltip("E.AllWidth","Set every level to one width");
      bool uniform=g_edit.count>0;
      for(int i=1;i<g_edit.count && uniform;i++)uniform=g_edit.levels[i].ink==g_edit.levels[0].ink;
      Button("E.AllColor","All",x+U(cols[5]),fy,52,22,uniform?g_edit.levels[0].ink:clrWhite);
      Tooltip("E.AllColor","Set every level to one colour");
      Label("E.Page",IntegerToString(g_page+1)+" / "+IntegerToString((int)MathMax(1,(g_edit.count+g_rows-1)/g_rows)),x+U(264),fy+U(4));
      // One-click switches for level groups, on the row of Save and Load.
      int gy=y+PanelHeight()-U(61);
      string groups[]={"Quadrants","Octants","OTE"};
      string gtips[]={"Show or hide the 25% and 75% levels","Show or hide the 12.5, 37.5, 62.5 and 87.5% levels","Show or hide the OTE levels: 62, 70.5 and 79%"};
      for(int g=0;g<3;g++)
        {
         int state=FPGroupState(g_edit,g+1);
         Button("E.Group"+IntegerToString(g+1),(state==1?"[x] ":"[ ] ")+groups[g],x+U(12+g*96),gy,92,22,state==0?clrGainsboro:clrWhite);
         Tooltip("E.Group"+IntegerToString(g+1),gtips[g]);
        }
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
   if(!g_hidden){BuildToolbar();if(g_editor)BuildEditor();else if(g_zeditor)BuildZonesPanel();else if(g_reditor)BuildRiskPanel();else if(g_peditor)BuildPointsPanel();else if(g_list)BuildList();if(RiskBarShown())BuildRiskBar();BuildPointChip();}
   UpdateStatusObjects(GetTickCount64());
   RegSweep(UIS(""));
  }

void RefreshPresetList()
  {
   g_preset_count=0;string filename,ext=g_preset_points?".fpt":(g_preset_zones?".fzp":".fpp");
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
   if(g_preset_points)
     {
      for(int i=g_preset_count-1;i>=0;i--)g_preset_names[i+2]=g_preset_names[i];
      g_preset_names[0]=FPP_BUILTIN_ICT;g_preset_names[1]=FPP_BUILTIN_OFF;g_preset_count+=2;
     }
   else if(g_preset_zones)
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
   if(!g_editor && !g_zeditor && !g_peditor)return;
   if(g_popup==4 && harvest)HarvestPresetName();
   ClosePopup();g_popup=4;g_preset_save=save_mode;g_preset_zones=g_zeditor;g_preset_points=g_peditor;
   if(reset_page){RefreshPresetList();g_preset_page=0;}
   g_preset_page=Lim(g_preset_page,0,(int)MathMax(0,(g_preset_count-1)/7));
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(20);
   if(g_popup_y+U(326)>g_height)g_popup_y=(int)MathMax(4,g_height-U(326)-4);
   int px=g_popup_x,py=g_popup_y;
   UIBase(Obj("R.Background"),OBJ_RECTANGLE_LABEL,px,py,U(360),U(326),"",clrWhiteSmoke,clrBlack,390);
   UIBase(Obj("R.Title"),OBJ_LABEL,px+U(10),py+U(8),0,0,g_preset_points?(save_mode?"Save price points preset":"Load or delete a price points preset"):g_preset_zones?(save_mode?"Save zones preset":"Load or delete a zones preset"):(save_mode?"Save configuration preset":"Load or delete a configuration preset"),clrWhite,clrBlack,400);
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
   UIBase(Obj("R.Message"),OBJ_LABEL,px+U(10),py+U(267),0,0,save_mode?"Choose a name; saving replaces that named preset.":(g_preset_points?"Loading replaces the price point list.":g_preset_zones?"Loading replaces the zone list; broker time is kept.":"Choose a preset; anchors stay unchanged."),clrWhite,clrBlack,400);
   if(!save_mode)UIBase(Obj("R.Delete"),OBJ_BUTTON,px+U(100),py+U(292),U(80),U(24),"Delete",clrMistyRose,clrBlack,400);
   if(!save_mode && !g_preset_zones && !g_preset_points)UIBase(Obj("R.Restore"),OBJ_BUTTON,px+U(220),py+U(236),U(128),U(23),"Restore built-ins",clrWhite,clrBlack,400);
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
   if((!g_editor && !g_zeditor && !g_peditor) || g_popup!=4)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Use a short name without path or special characters.");return;}
   if(g_preset_points){PointPresetAction();return;}
   if(g_preset_zones){ZonePresetAction();return;}
   string filename="FibonacciPro\\Presets\\"+g_preset_name+".fpp";
   if(g_preset_save)
     {
      if(!HarvestEdits()){PresetMessage("Correct the invalid properties before saving.");return;}
      FPSetup record=g_edit;
      if(FPUsesTierInk(record))record.base_color=clrNONE;   // keeps the preset coloured by timeframe
      if(!WritePreset(filename,record)){PresetMessage("Could not save preset. Check Experts log.");Print("Fibonacci Pro preset write error: ",GetLastError());return;}
      // Save is an explicit commit, not just a file export of an uncommitted draft.
      if(!ApplyEditor(false)){ClosePopup();Status("Preset file saved; applying or autosaving settings failed.");return;}
      Status(FPIsTypeName(g_preset_name)?"Saved preset "+g_preset_name+". New "+g_preset_name+" drawings use it.":"Saved preset: "+g_preset_name+".");
     }
   else
     {
      FPSetup loaded;
      if(!ReadPreset(filename,loaded) && !ReadPreset(filename+".bak",loaded)){PresetMessage("Preset missing or invalid; current settings retained.");return;}
      CopyConfig(g_edit,loaded);FPAfterPresetLoad(g_edit,loaded);g_page=0;ClosePopup();g_dirty=true;g_ui_dirty=true;
      Status("Loaded "+g_preset_name+". Apply or OK to keep it; Cancel to revert.");
     }
  }
// Two-step delete: the first click arms, a second click within 5 s removes the file.
void PresetDelete()
  {
   if((!g_editor && !g_zeditor && !g_peditor) || g_popup!=4 || g_preset_save)return;
   HarvestPresetName();
   if(!PresetNameValid()){PresetMessage("Select a preset to delete.");return;}
   if((g_preset_zones && ZoneBuiltin(g_preset_name)) || (g_preset_points && PointBuiltin(g_preset_name))){PresetMessage("Built-in presets can't be deleted.");return;}
   string filename="FibonacciPro\\Presets\\"+g_preset_name+(g_preset_points?".fpt":(g_preset_zones?".fzp":".fpp"));
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
   if(kind>=20){PPDropdown(kind,row);return;}
   bool zone=kind>=10;
   if(zone?!g_zeditor:!g_editor)return;
   if((kind==1 && (row<0 || row>=g_edit.count)) || (kind==2 && (row<-1 || row>=g_edit.count)))return; // width row -1: every level
   if(kind>=10 && kind<=12 && (row<0 || row>=g_zedit.count))return;
   string source=zone?(kind==10?UIS("Z.Style"+IntegerToString(row)):(kind==11?UIS("Z.Width"+IntegerToString(row)):(kind==12?UIS("Z.Label"+IntegerToString(row)):UIS("Z.Broker")))):kind==1?UIS("E.Style"+IntegerToString(row)):(kind==2?UIS(row<0?"E.AllWidth":"E.Width"+IntegerToString(row)):(kind==5?UIS("E.LblV"):(kind==6?UIS("E.LblH"):UIS("E.LblF"))));
   int ri=RegFind(source);if(ri<0)return;
   int sx=g_reg[ri].x,sy=g_reg[ri].y,sh=g_reg[ri].h;
   ClosePopup();g_popup=kind;g_popup_row=row;
   string items[];int current=0,w=110;
   if(kind==1){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=g_style_names[i];current=g_edit.levels[row].style;}
   else if(kind==2){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=IntegerToString(i+1);current=row<0?(g_edit.count>0?g_edit.levels[0].width-1:0):g_edit.levels[row].width-1;w=48;}
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
   if(g_popup>=20){PPDropdownChoice(choice);return;}
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
   if(g_popup==2 && g_popup_row==-1){for(int i=0;i<g_edit.count;i++)g_edit.levels[i].width=choice+1;return;}
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
   if(g_picker_target<=-2000)
     {
      int r=-g_picker_target-2000;
      if(g_peditor && r<g_pedit.count)g_pedit.rows[r].ink=ink;
      ClosePopup();PPPreview(false);g_ui_dirty=true;return;
     }
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
   bool point=target<=-2000;
   bool zone=target<=-1000 && !point;
   if(point){if(!g_peditor || -target-2000>=g_pedit.count)return;}
   else if(zone){if(!g_zeditor || -target-1000>=g_zedit.count)return;}
   else if(!g_editor || target>=g_edit.count || target<-5 || target==-1)return;
   if(target==-5 && g_edit.count==0){Status("Add a level first.");return;}
   ClosePopup();g_popup=3;g_picker_target=target;
   if(point)g_pick_color=g_pedit.rows[-target-2000].ink;
   else if(zone)g_pick_color=g_zedit.zones[-target-1000].ink;
   else if(target==-5)g_pick_color=g_edit.levels[0].ink;
   else g_pick_color=target>=0?g_edit.levels[target].ink:(target==-2?g_edit.fill_top:(target==-3?g_edit.fill_bottom:g_edit.base_color));
   RGBtoHSV(g_pick_color);
   g_popup_x=g_panel_x+U(50);g_popup_y=g_panel_y+U(28);
   if(g_popup_y+U(365)>g_height)g_popup_y=(int)MathMax(4,g_height-U(365)-4);
   UIBase(Obj("P.BG"),OBJ_RECTANGLE_LABEL,g_popup_x,g_popup_y,U(360),U(354),"",clrWhiteSmoke,clrBlack,350);
   UIBase(Obj("P.Title"),OBJ_LABEL,g_popup_x+U(10),g_popup_y+U(7),0,0,(point?"Colour - "+Clip(g_pedit.rows[-target-2000].name,30):zone?"Colour - "+Clip(g_zedit.zones[-target-1000].name,30):(target==-5?"One colour for every level":"All MT5 named colors + visual spectrum")),clrWhite,clrBlack,360);
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
   bool active=(g_editor && g_tab==4) || (g_zeditor && g_ztab==2) || (g_peditor && g_ptab==2);
   if(!active || g_hidden || !g_slider_on || g_popup!=0){g_slider_drag=false;return;}
   if(down && !was_down && x>=g_slider_x0-U(6) && x<=g_slider_x1+U(6) && y>=g_slider_y0 && y<=g_slider_y1)g_slider_drag=true;
   if(!down){g_slider_drag=false;return;}
   if(!g_slider_drag)return;
   int value=Lim((int)MathRound(100.0*(x-g_slider_x0)/MathMax(1,g_slider_x1-g_slider_x0)),0,100);
   if(value==(g_peditor?g_pedit.opacity:(g_zeditor?g_zedit.opacity:g_edit.opacity)))return;
   if(g_peditor){g_pedit.opacity=value;SetText(UIS("N.Opacity"),IntegerToString(value));PPPreview(false);}
   else if(g_zeditor){g_zedit.opacity=value;SetText(UIS("Z.Opacity"),IntegerToString(value));ZonePreview(false);}
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
string LevelText(FPLevel &level,const double price,const string name="")
  {string s=level.description;StringReplace(s,"%%",DoubleToString(level.value*100,1));StringReplace(s,"%$",DoubleToString(price,_Digits));StringReplace(s,"%n",name);return s;}
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
   hash=FPMix(hash,s.gradient?1:0);hash=FPMix(hash,s.opacity);hash=FPMix(hash,(long)s.source_tf);hash=FPMix(hash,s.used?1:0);
   return hash;
  }
void DrawLabel(FPSetup &s,const int slot,const int i,const int y)
  {
   double price=FPLevelPrice(s.pa,s.pb,s.levels[i].value);
   string text=LevelText(s.levels[i],price,s.name);
   if(StringLen(text)==0)return;
   int tw=g_line_canvas.TextWidth(text),th=g_line_canvas.TextHeight(text),half=(s.levels[i].width-1)/2;
   int tx=FPLabelX(g_geo[slot].xl,g_geo[slot].xr,g_geo[slot].l,g_geo[slot].r,tw,g_width,s.label_h,s.ray_left,s.ray_right,s.label_float,U(3));
   if(tx>=g_width || tx+tw<=0)return;
   int ty=s.label_v==1?y+(s.levels[i].width-half)+1:y-half-th-2;
   ty=Lim(ty,0,(int)MathMax(0,g_height-th));
   g_line_canvas.TextOut(tx,ty,text,ColorToARGB(s.levels[i].ink,s.used?(uchar)FP_USED_ALPHA:(uchar)255));
  }
void DrawSetup(FPSetup &s,const int slot,const bool selected)
  {
   if(!g_geo[slot].valid)return;
   int l=g_geo[slot].l,r=g_geo[slot].r;
   for(int i=0;i<s.count;i++)
     {
      int y=g_geo[slot].ly[i];
      if(y==FP_OFF || y<0 || y>=g_height)continue;
      HLine(l,r,y,s.levels[i].ink,s.levels[i].width,s.levels[i].style,s.used?(uchar)FP_USED_ALPHA:(uchar)255); // used drawings fade
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
   PPPrepare();
   RiskPrepare();
   bool sel=g_selected>=0 && g_selected<g_count;
   // The fill layer is re-uploaded only when its pixels would actually change
   // (each upload copies a full chart-sized bitmap to the terminal).
   ulong sig=FPMix(FPMix(FPMix((ulong)1469598103934665603,g_width),g_height),sel?g_selected:-1);
   for(int i=0;i<g_count;i++)
     {if(sel && g_editor && i==g_selected)sig=FillSignatureOf(g_edit,i,sig);else sig=FillSignatureOf(g_sets[i],i,sig);}
   sig=FPMix(FPMix(FPMix(sig,(long)g_zfill_sig),g_zact.cut),g_zact.fib_lower);
   sig=FPMix(sig,(long)g_ppfill_sig);
   sig=RiskFillSig(sig);
   if(sig!=g_fill_sig)
     {
      // Fib and zone shading blended in one pass, so neither wipes out the other.
      g_fill_canvas.Erase(0);
      ShadeDraw(sel);
      g_fill_canvas.Update(false);g_fill_sig=sig;
     }
   g_line_canvas.Erase(0);
   ZonesDraw();
   PPDraw();          // price points over the zones, under the drawings
   // Unselected first, selected last for predictable selection and stacking.
   for(int i=0;i<g_count;i++)if(i!=g_selected)DrawSetup(g_sets[i],i,false);
   if(sel){if(g_editor)DrawSetup(g_edit,g_selected,true);else DrawSetup(g_sets[g_selected],g_selected,true);}
   RiskDraw();        // the risk measurement over the drawings
   RiskCrosshair();
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
   else if(g_list_sort==2)c=StringCompare(FPKindLabel(g_sets[a]),FPKindLabel(g_sets[b]),false);
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
   Edit("L.Search",g_list_search,x+U(60),y+U(30),328);
   Tooltip("L.Search","Name or description; press Enter");
   Button("L.Find","Find",x+U(392),y+U(30),70);Button("L.Clear","Clear",x+U(466),y+U(30),70);
   // Filter (segmented) and bulk visibility
   string filters[]={"All","This TF","Fibs","Lines"};int fw[]={44,64,46,50};int fx=x+U(10);
   for(int i=0;i<4;i++){Button("L.F"+IntegerToString(i),filters[i],fx,y+U(58),fw[i],22,i==g_list_filter?clrLightSteelBlue:clrWhite);fx+=U(fw[i]+2);}
   Button("L.ShowAll","Show all here",x+U(328),y+U(58),104);Button("L.HideAll","Hide all here",x+U(434),y+U(58),104);
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
   Label("L.HUsed","Used",x+U(404),y+U(90));
   Label("L.HHere","Here",x+U(434),y+U(90));
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
      Label("L.Type"+n,FPKindLabel(g_sets[slot]),x+U(206),ry+U(4),clrDimGray);
      int tf=TFIndex(g_sets[slot].source_tf);
      Label("L.TF"+n,tf>=0?g_tf_names[tf]:"?",x+U(242),ry+U(4),clrDimGray);
      Label("L.Price"+n,ListPriceText(g_sets[slot]),x+U(278),ry+U(4),clrDimGray);
      bool here=Visible(g_sets[slot]);
      Button("L.Used"+n,g_sets[slot].used?"x":"",x+U(406),ry+U(1),24,20,g_sets[slot].used?clrGainsboro:clrWhite);
      Tooltip("L.Used"+n,g_sets[slot].used?"Used. Click to keep extending":"Mark as used");
      Button("L.Here"+n,Glyph(here?0x25CF:0x25CB),x+U(434),ry+U(1),24,20,here?clrHoneydew:clrWhite);
      Tooltip("L.Here"+n,(here?"Hide on ":"Show on ")+g_tf_names[g_tf]);
      Button("L.Go"+n,"Go",x+U(460),ry+U(1),28,20);Tooltip("L.Go"+n,"Scroll the chart to this drawing");
      Button("L.Edit"+n,"Edit",x+U(490),ry+U(1),30,20);
      bool arm=g_list_confirm==g_sets[slot].uid && GetTickCount64()<g_list_confirm_until;
      Button("L.Del"+n,Glyph(0xD7),x+U(522),ry+U(1),20,20,arm?clrRed:clrWhite);
      Tooltip("L.Del"+n,arm?"Click again to delete":"Delete");
     }
   if(g_list_n==0)
      Label("L.Empty",g_count==0?"No drawings yet. Click New Fib to draw one.":"No drawings match the search or filter.",x+U(16),y+U(120),clrDimGray);
   // Footer
   int fy=y+U(156+rows*24)-U(32);
   string info=g_list_n==0?"":"Showing "+IntegerToString(first+1)+"-"+IntegerToString((int)MathMin(g_list_n,first+rows))+" of "+IntegerToString(g_list_n);
   if(g_list_n<g_count){if(StringLen(info)>0)info+="  ";info+="(filtered from "+IntegerToString(g_count)+")";}
   Label("L.Info",info,x+U(10),fy+U(4),clrDimGray);
   Button("L.Prev","<",x+U(428),fy,26);
   Label("L.Page",IntegerToString(g_list_page+1)+" / "+IntegerToString(pages),x+U(460),fy+U(4));
   Button("L.Next",">",x+U(512),fy,26);
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
   if(g_reditor){Status("Close the Risk window first.");return;}
   if(g_peditor){Status("Close the Price points window first.");return;}
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
   string actions[]={"L.Here","L.Go","L.Edit","L.Del","L.Used"};
   for(int a=0;a<5;a++)
     {
      if(StringFind(key,actions[a])!=0)continue;
      int r=(int)StringToInteger(StringSubstr(key,StringLen(actions[a])));
      if(r<0 || r>=g_list_rows)return;
      int slot=g_list_rowslot[r];
      if(slot<0 || slot>=g_count)return;
      if(a==0)ListToggleHere(slot);
      else if(a==1)GoTo(slot);
      else if(a==2){g_selected=slot;g_list=false;g_dirty=true;OpenEditor();}
      else if(a==3)ListDelete(slot);
      else ListToggleUsed(slot);
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
   if(c.days_back<1 || c.days_back>120 || c.dow_mask<0 || c.dow_mask>127 || c.broker_mode<0 || c.broker_mode>4 || c.broker_gmt<-12 || c.broker_gmt>14
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
// Every field set, zones beyond the count too, so a whole-config copy carries no stale data.
void FPZClear(FPZoneConfig &c)
  {
   c.enabled=false;c.upcoming=false;c.fill=false;c.gradient=false;c.fade_old=false;c.lines_full=false;c.declutter=false;c.highlight=false;
   c.hover=false;c.alert_sound=false;c.alert_push=false;
   for(int g=0;g<FPZ_GROUPS;g++){c.group_on[g]=false;c.group_tf[g]=0;}
   c.days_back=1;c.dow_mask=0;c.broker_mode=0;c.broker_gmt=0;c.fill_mode=0;c.opacity=0;c.label_size=11;c.alert_lead=0;
   c.cut=0;c.fib_lower=0;c.count=0;
   for(int i=0;i<FPZ_MAX;i++)FPZoneSet(c.zones[i],"",0,0,0,clrNONE,false);
  }
bool FPZReadFile(const string filename,FPZoneConfig &c)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   FPZoneConfig candidate;
   FPZClear(candidate);
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
   int days=Lim(g_zact.days_back,1,120);
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
   int n=FPPCopy(g_zocc[i].ts,stop,now,r);   // M5 where the terminal has no M1
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
   int n=FPPCopy(from,stop,now,r);
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
   double a=s.opacity/100.0*FibShadeFactor(s)*(s.used?.4:1.0);   // used drawings fade
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
   int cap=g_count+g_zfill_n+g_ppfill_n+3;
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
   n=PPShade(g_shade,n);     // price point zones and ranges: neutral, like the risk box
   n=RiskShade(g_shade,n);   // the risk box: not cut by zones, never cutting
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
   if(g_reditor){Status("Close the Risk window first.");return;}
   if(g_peditor){Status("Close the Price points window first.");return;}
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
   else if(key=="Days"){if(Numeric(text)){g_zedit.days_back=Lim((int)StringToInteger(text),1,120);rebuild=true;}else accepted=false;}
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

// ---------------------------------------------------------------- drawing types (1.65)
// Colour shows the timeframe a drawing was made on; the line form shows its type.
color FPTierColor(const ENUM_TIMEFRAMES tf)
  {
   int i=TFIndex(tf);                   // 0 = M1 ... 18 = D1, 19 = W1, 20 = MN1
   if(i>=20)return InpColorMN;
   if(i==19)return InpColorW1;
   if(i==18)return InpColorD1;
   if(i>=14)return InpColorH4;          // H4, H6, H8, H12
   if(i>=11)return InpColorH1;          // H1, H2, H3
   if(i>=8)return InpColorM15;          // M15, M20, M30
   if(i>=4)return InpColorM5;           // M5, M6, M10, M12
   return InpColorM1;                   // M1 to M4
  }
int FPTierWidth(const ENUM_TIMEFRAMES tf){return Lim(TFIndex(tf)>=18?InpWidthHigh:InpWidthLow,1,5);}
string FPTfTag(const ENUM_TIMEFRAMES tf)
  {int i=TFIndex(tf);if(i<0)return "?";return i==20?"MN":g_tf_names[i];}
string FPKindName(const int kind)
  {
   string names[]={"Fib","FVG","VI","UFVG","SPB","OB","PW","DW","KH","KL","KR"};
   return names[Lim(kind,0,FPK_COUNT-1)];
  }
string FPKindLabel(FPSetup &s){return (s.kind==FPK_NONE && s.hline)?"Line":FPKindName(s.kind);}
string FPDefaultName(FPSetup &s)
  {
   string name=FPTfTag(s.source_tf)+" "+FPKindLabel(s)+" "+IntegerToString(FPNextNumber(s));
   if(s.dir==1)name+=" "+Glyph(0x25B2);
   else if(s.dir==2)name+=" "+Glyph(0x25BC);
   return name;
  }
bool FPIsOte(const double value)
  {return MathAbs(value-.62)<1e-9 || MathAbs(value-.705)<1e-9 || MathAbs(value-.79)<1e-9;}
string FPLevelNumber(const double value)
  {
   string text=DoubleToString(value*100,1);
   if(StringSubstr(text,StringLen(text)-2)==".0")text=StringSubstr(text,0,StringLen(text)-2);
   return text;
  }
void FPSetLevel(FPLevel &level,const double value,const bool on,const int style,const int width,const color ink,const string text)
  {level.enabled=on;level.value=value;level.description=text;level.style=style;level.width=width;level.ink=ink;}
// Every level slot gets a defined value, so whole-drawing copies never carry leftovers.
void FPClearLevels(FPSetup &s)
  {for(int i=0;i<FP_MAX_LEVELS;i++)FPSetLevel(s.levels[i],0,false,STYLE_SOLID,1,clrNONE,"");}
bool FPGapKind(const int kind)
  {return kind==FPK_FVG || kind==FPK_VI || kind==FPK_UFVG || kind==FPK_SPB || kind==FPK_PW || kind==FPK_DW;}
// Factory style of a type. Gaps have dashed boundaries, OB and KR solid ones; quadrants
// are dash-dot, octants dash-dot-dot, the CE dotted; OTE lines are white, thin, solid and
// numbered. Boundaries, quadrants and the CE are on. Colour and width follow the timeframe
// when the style is applied (base colour clrNONE marks "by timeframe").
void FPFactoryStyle(const int kind,FPSetup &s)
  {
   FPClearLevels(s);
   s.uid=0;s.name="";s.description="";s.ta=0;s.tb=0;s.pa=0;s.pb=0;s.left=0;s.right=0;
   s.kind=FPK_NONE;s.dir=0;s.used=false;s.used_ray=false;
   s.ray_left=false;s.ray_right=true;s.anchors_locked=false;s.diagonal=false;s.labels=true;
   s.label_v=0;s.label_h=1;s.label_float=true;s.hline=(kind==FPK_KH || kind==FPK_KL);
   s.base_color=clrNONE;s.fill=false;s.gradient=false;s.fill_rays=true;
   s.fill_top=clrRoyalBlue;s.fill_bottom=clrPowderBlue;s.opacity=12;
   s.source_tf=(ENUM_TIMEFRAMES)_Period;s.visibility_mode=1;s.visible_mask=Allowed(s.source_tf);
   color ink=FPTierColor(s.source_tf);
   if(s.hline){s.count=1;FPSetLevel(s.levels[0],0,true,STYLE_SOLID,1,ink,"%n");return;}
   int edge=FPGapKind(kind)?STYLE_DASH:STYLE_SOLID;
   double v[]={0,.125,.25,.375,.5,.62,.625,.705,.75,.79,.875,1};
   s.count=ArraySize(v);
   for(int i=0;i<s.count;i++)
     {
      double x=v[i];
      bool boundary=(x==0 || x==1),quadrant=(x==.25 || x==.75),ce=(x==.5),ote=FPIsOte(x);
      int style=boundary?edge:(quadrant?STYLE_DASHDOT:(ce?STYLE_DOT:(ote?STYLE_SOLID:STYLE_DASHDOTDOT)));
      FPSetLevel(s.levels[i],x,boundary || quadrant || ce,style,1,ote?clrWhite:ink,x==0?"%n":(ote?FPLevelNumber(x):""));
     }
  }
// Every level except OTE takes the timeframe's colour and width.
void FPApplyTierInk(FPSetup &s)
  {
   color ink=FPTierColor(s.source_tf);int width=FPTierWidth(s.source_tf);
   for(int i=0;i<s.count;i++)
     {if(FPIsOte(s.levels[i].value))continue;s.levels[i].ink=ink;s.levels[i].width=width;}
   s.base_color=ink;
  }
bool FPUsesTierInk(FPSetup &s)
  {
   color ink=FPTierColor(s.source_tf);
   for(int i=0;i<s.count;i++)if(!FPIsOte(s.levels[i].value) && s.levels[i].ink!=ink)return false;
   return s.count>0;
  }
// The name tag (%n) sits above the upper boundary: level prices run from pb at 0% to pa at 100%.
void FPPlaceTag(FPSetup &s)
  {
   int e0=-1,e1=-1;
   for(int i=0;i<s.count;i++){if(s.levels[i].value==0.0)e0=i;else if(s.levels[i].value==1.0)e1=i;}
   if(e0<0 || e1<0)return;
   int upper=s.pb>s.pa?e0:e1,lower=upper==e0?e1:e0;
   if(s.levels[lower].description=="%n" && s.levels[upper].description=="")
     {s.levels[upper].description="%n";s.levels[lower].description="";}
  }
// A horizontal line keeps its price when its levels change.
void FPKeepLinePrice(FPSetup &s,const double price)
  {
   int k=LineLevel(s);
   if(k<0){k=BoundaryLevel(s);if(k<0)return;s.levels[k].enabled=true;}
   double delta=MathAbs(s.pa-s.pb);
   if(delta<=0)delta=LineSpan();
   double v=s.levels[k].value;
   if(v==0.0){s.pb=price;s.pa=NormalizeDouble(price+delta,_Digits);}
   else {s.pa=NormalizeDouble(price+(1.0-v)*delta,_Digits);s.pb=NormalizeDouble(s.pa-delta,_Digits);}
  }
// The style for a type: your own preset of that name (e.g. "FVG") if you saved one, else
// the factory style. Unmatched drawings use the KR style (lines the KH style).
int FPStyleKind(FPSetup &s,const int kind){return kind!=FPK_NONE?kind:(s.hline?FPK_KH:FPK_KR);}
void FPTypePreset(const int kind,FPSetup &style)
  {if(!ReadPreset("FibonacciPro\\Presets\\"+FPKindName(kind)+".fpp",style))FPFactoryStyle(kind,style);}
void ApplyTypeStyle(FPSetup &s,const int kind,const int dir)
  {
   FPSetup style;
   FPTypePreset(FPStyleKind(s,kind),style);
   bool line=s.hline,ray=s.ray_right;int k=LineLevel(s);
   double price=(line && k>=0)?FPLevelPrice(s.pa,s.pb,s.levels[k].value):0;
   CopyConfig(s,style);
   if(line){FPKeepLinePrice(s,price);s.ray_right=ray;}   // a line keeps its extent: rayed when clicked, fixed when dragged
   s.visible_mask|=(long)1<<TFIndex(s.source_tf);
   FPApplyTierInk(s);FPPlaceTag(s);
   s.kind=kind;s.dir=dir;s.name=FPDefaultName(s);
  }
// "Defaults" on the Fibo levels tab: the factory level set of this drawing's type.
void FPResetLevels(FPSetup &s)
  {
   FPSetup style;
   FPFactoryStyle(FPStyleKind(s,s.kind),style);
   int k=LineLevel(s);
   double price=(s.hline && k>=0)?FPLevelPrice(s.pa,s.pb,s.levels[k].value):0;
   s.count=style.count;
   for(int i=0;i<s.count;i++)s.levels[i]=style.levels[i];
   if(s.hline)FPKeepLinePrice(s,price);
   FPApplyTierInk(s);FPPlaceTag(s);
  }
void FPAfterPresetLoad(FPSetup &s,FPSetup &loaded)
  {if(loaded.base_color==clrNONE)FPApplyTierInk(s);FPPlaceTag(s);}

// ---- type detection from the two snapped anchors
bool FPNear(const double a,const double b,const double tol){return MathAbs(a-b)<=tol;}
double FPBodyTop(MqlRates &k){return MathMax(k.open,k.close);}
double FPBodyBot(MqlRates &k){return MathMin(k.open,k.close);}
// c: the bars from the earlier to the later anchor; ia/ib: the anchor bars (ib<0 for a
// single click); pa/pb: the anchor prices. dir: 1 bullish, 2 bearish, 0 none.
int FPDetectKind(MqlRates &c[],const int ia,const double pa,const int ib,const double pb,const double tol,int &dir)
  {
   dir=0;
   int n=ArraySize(c);
   if(ia<0 || ia>=n || ib>=n)return FPK_NONE;
   if(ib<0)
     {
      if(FPNear(pa,c[ia].high,tol))return FPK_KH;
      if(FPNear(pa,c[ia].low,tol))return FPK_KL;
      return FPK_NONE;
     }
   if(ia==ib)
     {
      // One candle: its wicks, or an order block covering its whole body.
      double hi=MathMax(pa,pb),lo=MathMin(pa,pb),top=FPBodyTop(c[ia]),bot=FPBodyBot(c[ia]);
      int side=c[ia].close<c[ia].open?1:(c[ia].close>c[ia].open?2:0);   // a down-close candle is a bullish OB
      bool h=FPNear(hi,c[ia].high,tol),l=FPNear(lo,c[ia].low,tol);
      if(h && l){dir=side;return FPK_OB;}
      if(h && FPNear(lo,top,tol) && top<c[ia].high-tol)return FPK_PW;
      if(l && FPNear(hi,bot,tol) && bot>c[ia].low+tol)return FPK_DW;
      if((h && FPNear(lo,bot,tol)) || (l && FPNear(hi,top,tol)) || (FPNear(hi,top,tol) && FPNear(lo,bot,tol) && top>bot+tol))
        {dir=side;return FPK_OB;}
      return FPK_NONE;
     }
   int i=MathMin(ia,ib),j=MathMax(ia,ib),span=j-i+1;
   double pi=ia<ib?pa:pb,pj=ia<ib?pb:pa;
   if(span==2)
     {
      // Neighbouring candles, body edge to body edge, the bodies apart: a volume imbalance.
      if(FPBodyTop(c[i])<FPBodyBot(c[j])-tol && FPNear(pi,FPBodyTop(c[i]),tol) && FPNear(pj,FPBodyBot(c[j]),tol)){dir=1;return FPK_VI;}
      if(FPBodyBot(c[i])>FPBodyTop(c[j])+tol && FPNear(pi,FPBodyBot(c[i]),tol) && FPNear(pj,FPBodyTop(c[j]),tol)){dir=2;return FPK_VI;}
     }
   if(span==3)
     {
      // Candles 1-3. The drawn range decides: the FVG's own edges (FVG); the FVG plus one
      // volume imbalance beside the middle candle (UFVG); or from the far edge of the lower
      // imbalance to the far edge of the upper one (SPB, which needs no FVG).
      double lo=MathMin(pi,pj),hi=MathMax(pi,pj);
      for(int pass=0;pass<2;pass++)
        {
         bool up=(pass==0);
         MqlRates a=c[i],m=c[i+1],b=c[j];
         bool vi1=up?FPBodyTop(a)<FPBodyBot(m)-tol:FPBodyBot(a)>FPBodyTop(m)+tol;
         bool vi2=up?FPBodyTop(m)<FPBodyBot(b)-tol:FPBodyBot(m)>FPBodyTop(b)+tol;
         double v1lo=up?FPBodyTop(a):FPBodyTop(m),v1hi=up?FPBodyBot(m):FPBodyBot(a);
         double v2lo=up?FPBodyTop(m):FPBodyTop(b),v2hi=up?FPBodyBot(b):FPBodyBot(m);
         double wick1=up?a.high:a.low,body1=up?FPBodyTop(a):FPBodyBot(a);
         double wick3=up?b.low:b.high,body3=up?FPBodyBot(b):FPBodyTop(b);
         if(!(FPNear(pi,wick1,tol) || FPNear(pi,body1,tol)) || !(FPNear(pj,wick3,tol) || FPNear(pj,body3,tol)))continue;
         if(up?!(pi<pj):!(pi>pj))continue;
         int d=up?1:2;
         if(vi1 && vi2 && FPNear(pi,body1,tol) && FPNear(pj,body3,tol)){dir=d;return FPK_SPB;}
         bool fvg=up?a.high<b.low-tol:a.low>b.high+tol;
         if(!fvg)continue;
         int count=((vi1 && v1lo>=lo-tol && v1hi<=hi+tol)?1:0)+((vi2 && v2lo>=lo-tol && v2hi<=hi+tol)?1:0);
         dir=d;
         return count==0?FPK_FVG:(count==1?FPK_UFVG:FPK_SPB);
        }
     }
   // A low and a high on different candles, the low below the high: a key range.
   if((FPNear(pi,c[i].low,tol) && FPNear(pj,c[j].high,tol) && pi<pj) || (FPNear(pi,c[i].high,tol) && FPNear(pj,c[j].low,tol) && pj<pi))
      return FPK_KR;
   return FPK_NONE;
  }
int DetectKind(FPSetup &s,int &dir)
  {
   dir=0;
   datetime t0=(datetime)MathMin((long)s.ta,(long)s.tb),t1=(datetime)MathMax((long)s.ta,(long)s.tb);
   MqlRates r[];
   int got=CopyRates(_Symbol,s.source_tf,t0,t1,r);
   if(got<=0)return FPK_NONE;
   int ia=-1,ib=-1;
   for(int k=0;k<got;k++){if(r[k].time==s.ta)ia=k;if(r[k].time==s.tb)ib=k;}
   if(ia<0 || ib<0)return FPK_NONE;
   return FPDetectKind(r,ia,s.pa,ib,s.pb,_Point*.5,dir);
  }
int DetectLineKind(FPSetup &s,int &dir)
  {
   dir=0;
   int k=LineLevel(s);
   if(k<0)return FPK_NONE;
   MqlRates r[];
   if(CopyRates(_Symbol,s.source_tf,s.left,s.left,r)!=1 || r[0].time!=s.left)return FPK_NONE;
   return FPDetectKind(r,0,FPLevelPrice(s.pa,s.pb,s.levels[k].value),-1,0,_Point*.5,dir);
  }
// Runs once, when a drawing is created: its type, style, colour, width and name.
void AutoType(FPSetup &s)
  {
   int dir=0,kind=s.hline?DetectLineKind(s,dir):DetectKind(s,dir);
   ApplyTypeStyle(s,kind,dir);
  }
string FPCreatedStatus(FPSetup &s,const bool line)
  {
   if(line)return s.name+" placed. Drag it to move it; double-click for properties.";
   if(s.kind==FPK_NONE)return s.name+" drawn. No pattern matched its anchors, so it has the KR style.";
   return s.name+" drawn. Double-click it to rename or restyle.";
  }

// ---- "Used": stop extending at the first candle that traded into the drawing
datetime FPUsedStop(FPSetup &s)
  {
   datetime start=s.hline?s.left:(datetime)MathMax((long)s.ta,(long)s.tb);
   if(s.hline || (s.kind!=FPK_KR && s.kind!=FPK_NONE))
     {
      double lo=MathMin(s.pa,s.pb),hi=MathMax(s.pa,s.pb);
      if(s.hline){int k=LineLevel(s);if(k>=0){lo=FPLevelPrice(s.pa,s.pb,s.levels[k].value);hi=lo;}}
      MqlRates r[];
      int got=CopyRates(_Symbol,(ENUM_TIMEFRAMES)_Period,start+1,TimeCurrent(),r);
      for(int k=0;k<got;k++)if(r[k].low<=hi && r[k].high>=lo)return r[k].time;
     }
   datetime last=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0);       // a range, or untouched: now
   return last>start?last:start+(datetime)PeriodSeconds();
  }
void MarkUsed(FPSetup &s,const bool on)
  {
   if(on==s.used)return;
   if(on)
     {
      s.used_ray=s.ray_right;
      datetime stop=FPUsedStop(s);
      if(stop>s.left)s.right=stop;
      s.ray_right=false;s.used=true;
     }
   else {s.ray_right=s.used_ray;s.used=false;}
  }

// ---- Fibo levels tab: sort, move, group switches
void FPSortLevels(FPSetup &s,const bool desc)
  {
   for(int i=1;i<s.count;i++)
     {
      FPLevel keep=s.levels[i];int j=i;
      while(j>0 && (desc?s.levels[j-1].value<keep.value:s.levels[j-1].value>keep.value)){s.levels[j]=s.levels[j-1];j--;}
      s.levels[j]=keep;
     }
  }
void MoveLevel(FPSetup &s,const int from,const int to)
  {
   if(from==to || from<0 || to<0 || from>=s.count || to>=s.count)return;
   FPLevel keep=s.levels[from];
   if(from<to)for(int k=from;k<to;k++)s.levels[k]=s.levels[k+1];
   else for(int k=from;k>to;k--)s.levels[k]=s.levels[k-1];
   s.levels[to]=keep;
  }
// Groups: 1 quadrants (25, 75), 2 octants (12.5, 37.5, 62.5, 87.5), 3 OTE (62, 70.5, 79).
bool FPInGroup(const double v,const int group)
  {
   if(group==1)return MathAbs(v-.25)<1e-9 || MathAbs(v-.75)<1e-9;
   if(group==2)return MathAbs(v-.125)<1e-9 || MathAbs(v-.375)<1e-9 || MathAbs(v-.625)<1e-9 || MathAbs(v-.875)<1e-9;
   return FPIsOte(v);
  }
// 0: the drawing has none of these levels, 1: all on, 2: some or all off.
int FPGroupState(FPSetup &s,const int group)
  {
   int present=0,on=0;
   for(int i=0;i<s.count;i++)if(FPInGroup(s.levels[i].value,group)){present++;if(s.levels[i].enabled)on++;}
   return present==0?0:(on==present?1:2);
  }
void FPToggleGroup(FPSetup &s,const int group)
  {
   bool turn_on=FPGroupState(s,group)==2;
   for(int i=0;i<s.count;i++)if(FPInGroup(s.levels[i].value,group))s.levels[i].enabled=turn_on;
  }
// Drag a row's handle up or down to move that level; a blue line shows where it lands.
int LevelRowY(const int row){return g_panel_y+U(64)+U(21)+U(row*24);}
void LevelDragMouse(const int x,const int y,const bool down,const bool was_down)
  {
   if(down && !was_down)
     {
      if(!g_editor || g_tab!=2 || g_popup!=0 || g_hidden)return;
      int start=g_page*g_rows;
      for(int row=0;row<g_rows && start+row<g_edit.count;row++)
        {
         int ri=RegFind(UIS("E.Drag"+IntegerToString(start+row)));
         if(ri<0)continue;
         if(x>=g_reg[ri].x && x<g_reg[ri].x+g_reg[ri].w && y>=g_reg[ri].y && y<g_reg[ri].y+g_reg[ri].h)
           {g_lvdrag=true;g_lvdrag_from=start+row;g_lvdrag_to=g_lvdrag_from;HoldScroll();return;}
        }
      return;
     }
   if(!g_lvdrag)return;
   if(!g_editor || g_tab!=2){g_lvdrag=false;RegDelete(UIS("E.Drop"));ReleaseScroll();return;}
   int start=g_page*g_rows,last=(int)MathMin(g_edit.count,start+g_rows)-1;
   int rel=(int)MathFloor((y-LevelRowY(0))/(double)U(24));
   int to=Lim(start+rel,start,(int)MathMax(start,last));
   if(down)
     {
      g_lvdrag_to=to;
      if(to==g_lvdrag_from)RegDelete(UIS("E.Drop"));
      else Box("E.Drop",g_panel_x+U(8),to>g_lvdrag_from?LevelRowY(to-start)+U(23):LevelRowY(to-start)-U(2),FP_PANEL_WIDTH-16,2,clrDodgerBlue);
      ChartRedraw();
      return;
     }
   g_lvdrag=false;RegDelete(UIS("E.Drop"));ReleaseScroll();
   g_ignore_editor_click_until=GetTickCount64()+300;   // the release must not click the button under it
   if(g_lvdrag_to!=g_lvdrag_from){MoveLevel(g_edit,g_lvdrag_from,g_lvdrag_to);g_dirty=true;}
   g_ui_dirty=true;
  }

// ---- built-in presets: one per type plus KR + OTE. They are ordinary preset files, so
// they can be edited, re-saved or deleted; Restore built-ins writes them again.
string FPBuiltinName(const int i){return i<10?FPKindName(i+1):"KR + OTE";}
void FPBuiltinStyle(const int i,FPSetup &s)
  {
   FPFactoryStyle(i<10?i+1:FPK_KR,s);
   if(i==10)for(int k=0;k<s.count;k++)if(FPIsOte(s.levels[k].value))s.levels[k].enabled=true;
  }
int FPInstallBuiltins(const bool overwrite)
  {
   int written=0;
   for(int i=0;i<FP_BUILTIN_COUNT;i++)
     {
      string file="FibonacciPro\\Presets\\"+FPBuiltinName(i)+".fpp";
      if(!overwrite && FileIsExist(file))continue;
      FPSetup s;FPBuiltinStyle(i,s);
      if(WritePreset(file,s))written++;
     }
   return written;
  }
// First run only, so that deleted built-ins stay deleted.
void FPInstallBuiltinsOnce()
  {
   if(FileIsExist(FP_BUILTIN_MARKER))return;
   FPInstallBuiltins(false);
   int f=FileOpen(FP_BUILTIN_MARKER,FILE_WRITE|FILE_BIN);
   if(f!=INVALID_HANDLE){FileWriteInteger(f,1);FileClose(f);}
  }
void FPRestoreBuiltins()
  {
   ulong now=GetTickCount64();
   if(now>g_restore_confirm_until){g_restore_confirm_until=now+5000;PresetMessage("Click again: built-ins replace same-named presets.");return;}
   g_restore_confirm_until=0;
   int n=FPInstallBuiltins(true);
   RefreshPresetList();PresetBrowser(false,false,false);
   PresetMessage(n==FP_BUILTIN_COUNT?"Built-in presets restored.":"Some built-ins could not be written.");
  }
bool FPIsBuiltinName(const string name)
  {for(int i=0;i<FP_BUILTIN_COUNT;i++)if(FPBuiltinName(i)==name)return true;return false;}
bool FPIsTypeName(const string name)
  {for(int k=1;k<FPK_COUNT;k++)if(FPKindName(k)==name)return true;return false;}
// The Used switch in the drawings list: saved at once, like Show/Hide.
void ListToggleUsed(const int slot)
  {
   if(slot<0 || slot>=g_count)return;
   FPSetup previous=g_sets[slot];
   MarkUsed(g_sets[slot],!g_sets[slot].used);
   if(!Save()){g_sets[slot]=previous;Status("Could not save the drawings file; nothing changed.");}
   else Status(g_sets[slot].name+(g_sets[slot].used?" marked as used.":" extends again."));
   g_dirty=true;g_ui_dirty=true;
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
   if(StringLen(s.levels[k].description)>0 && s.levels[k].description!=FP_DEFAULT_TEXT && s.levels[k].description!="%n")lines[n++]="Label\t"+Clip(LevelText(s.levels[k],price,s.name),40);
   lines[n++]="Price\t"+DoubleToString(price,_Digits);
   lines[n++]="Anchored on\t"+(source>=0?g_tf_names[source]:"?");
   if(s.used)lines[n++]="Status\tUsed";
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
   bool allowed=(InpHoverCandleInfo || InpHoverFibInfo || (g_zact.enabled && g_zact.hover) || (g_pact.enabled && g_pact.hover)) && g_mouse_in && !g_prev_down && g_drag==0 && !g_toolbar_drag
                && !g_slider_drag && !g_zdrag && !g_ppdrag && g_picker_drag==0 && g_popup==0 && !g_risk.armed && g_rdrag==0 && !HitUI(x,y);
   if(!allowed)return HideTip();
   string lines[];color accent=clrNONE;int slot=-1,level=-1,shift=-1,zocc=-1,zkind=0,pocc=-1,ppart=-1;
   if(InpHoverFibInfo && FindFibAt(x,y,slot,level))
     {if(g_editor && slot==g_selected)FibTip(g_edit,level,lines,accent);else FibTip(g_sets[slot],level,lines,accent);}
   else if(g_pact.enabled && g_pact.hover && FindPPAt(x,y,pocc,ppart))PPTip(pocc,ppart,lines,accent);
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
   if(g_reditor && x>=g_panel_x && x<=g_panel_x+U(FP_PANEL_WIDTH) && y>=g_panel_y && y<=g_panel_y+RiskPanelHeight())return true;
   if(g_peditor && x>=g_panel_x && x<=g_panel_x+U(FPP_PANEL_WIDTH) && y>=g_panel_y && y<=g_panel_y+PanelHeight())return true;
   if(HitPointChip(x,y))return true;
   if(RiskBarShown() && y>=RiskBarY() && y<=RiskBarY()+U(22) && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH))return true;
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
   if(g_risk.armed)RiskClear();   // a risk measurement being made; a finished one stays
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
   if(g_ppdrag)PPDragCancel();
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
   if(!HitCloseButton(x,y) && !HitZonesButton(x,y) && !HitRiskButton(x,y) && !HitPointsButton(x,y) && !HitShareButton(x,y) && !g_hidden && !g_armed && g_drag==0 && g_popup==0 && x>=g_toolbar_x && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH) && y>=g_toolbar_y && y<g_toolbar_y+U(21))
     {g_toolbar_drag=true;g_toolbar_moved=false;g_toolbar_dx=x-g_toolbar_x;g_toolbar_dy=y-g_toolbar_y;HoldScroll();return;}
   if(HitUI(x,y))return;
   if(g_popup!=0){ClosePopup();return;}
   // The risk tool first: while armed every chart press is its own, and its lines can be grabbed.
   if(RiskPress(x,y))return;
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
   if(PPDragBegin(x,y))return;   // the grip at a selected price point's right end
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
   // Price points: a click on one (not on a drawing) selects it; a click anywhere else clears it.
   if(hit<0 && PPPress(x,y)){if(g_selected>=0){g_selected=-1;g_dirty=true;g_ui_dirty=true;}g_last_hit=-1;return;}
   PPClearSel();
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
   BuildToolbar();if(RiskBarShown())BuildRiskBar();if(g_status_shown)UpdateStatusObjects(GetTickCount64());
   ChartRedraw();
  }
void MoveMouse(const int x,const int y)
  {
   if(g_rdrag!=0){RiskMove(x,y);return;}
   if(g_ppdrag){PPDragMove(x,y);return;}
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
   if(g_rdrag!=0){RiskMove(x,y);RiskRelease();return;}
   if(g_ppdrag){PPDragMove(x,y);PPDragEnd();return;}
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
   if(created)AutoType(g_sets[g_selected]); // type, style, colour, width and name from its anchors
   g_created=-1;g_drag=0;g_armed=false;ReleaseScroll();g_ui_dirty=true;g_dirty=true;
   if(!Save())
     {
      if(created){g_count--;g_selected=g_previous_selection;}
      else g_sets[g_selected]=g_drag_backup;
      g_dirty=true;return;
     }
   if(created && !line && !RememberConfig(g_sets[g_selected]))return; // it reports its own failure
   Status(created?FPCreatedStatus(g_sets[g_selected],line):"Drawings saved. Select a line; double-click a line for properties.");
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
   bool want=g_armed || g_drag!=0 || g_toolbar_drag || g_slider_drag || g_picker_drag!=0 || g_zdrag || g_ppdrag || g_lvdrag || g_risk.armed || g_rdrag!=0;
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
   LevelDragMouse(x,y,down,was_down);
   if(down && !was_down)BeginMouse(x,y);
   else if(down && (g_drag!=0 || g_toolbar_drag || g_zdrag || g_ppdrag || g_rdrag!=0))MoveMouse(x,y);
   else if(down)g_view_probe=true;
   else if(was_down || g_drag!=0 || g_toolbar_drag || g_zdrag || g_ppdrag || g_rdrag!=0)FinishPointer(x,y);
   if(!down && g_risk.armed)RiskHover(x,y);
   if((down || was_down) && g_drag==0 && !g_toolbar_drag && !g_zdrag && !g_ppdrag && g_rdrag==0 && !g_editor && g_popup==0 && !HitUI(x,y))
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
      if(name!=Obj("R.Restore"))g_restore_confirm_until=0;
      if(name==Obj("R.Cancel")){ClosePopup();return;}
      if(name==Obj("R.Action")){PresetAction();return;}
      if(name==Obj("R.Delete")){PresetDelete();return;}
      if(name==Obj("R.Restore")){FPRestoreBuiltins();return;}
      if(name==Obj("R.Prev")){g_preset_page=(int)MathMax(0,g_preset_page-1);PresetBrowser(g_preset_save,false);return;}
      if(name==Obj("R.Next")){g_preset_page=(int)MathMin((int)MathMax(0,(g_preset_count-1)/7),g_preset_page+1);PresetBrowser(g_preset_save,false);return;}
      if(StringFind(name,Obj("R.Item"))==0)
        {int i=(int)StringToInteger(StringSubstr(name,StringLen(Obj("R.Item"))));if(i>=0 && i<g_preset_count){g_preset_name=g_preset_names[i];PresetBrowser(g_preset_save,false,false);}return;}
      return;
     }
   if(g_popup==4)return;
   if(StringFind(name,Obj("Q."))==0){if(type==OBJ_BUTTON){if(g_popup==16)PPPopupClick(name);else if(g_popup==17)SharePopupClick(name);else ZonePopupClick(name);}return;}
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
   if(key=="T.Risk"){RiskButton();return;}
   if(key=="T.Points"){if(g_peditor)ClosePoints();else OpenPoints();return;}
   if(key=="T.Share"){if(g_popup==17)ClosePopup();else OpenShare();return;}
   if(StringFind(key,"N.")==0){if(type==OBJ_BUTTON && g_peditor)PointsClick(StringSubstr(key,2));return;}
   if(StringFind(key,"X.")==0){if(type==OBJ_BUTTON)PPChipClick(StringSubstr(key,2));return;}
   if(StringFind(key,"K.")==0){if(type==OBJ_BUTTON)RiskBarClick(StringSubstr(key,2));return;}
   if(StringFind(key,"W.")==0){if(type==OBJ_BUTTON && g_reditor)RiskPanelClick(StringSubstr(key,2));return;}
   if(StringFind(key,"Z.")==0){if(type==OBJ_BUTTON && g_zeditor)ZonesClick(StringSubstr(key,2));return;}
   if(StringFind(key,"L.")==0){if(type==OBJ_BUTTON && g_list)ListClick(key);return;}
   if(key=="T.Prev" || key=="T.Next"){SelectNext(key=="T.Next"?1:-1);return;}
   // Labels, edit boxes and the slider track are not commands.
   if(!g_editor || StringFind(key,"E.")!=0 || type!=OBJ_BUTTON)return;
   if(GetTickCount64()<g_ignore_editor_click_until)return; // the end of a level drag
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
   if(key=="AllWidth"){Dropdown(2,-1);return;}
   if(key=="FillTop"){Palette(-2);return;}if(key=="FillBottom"){Palette(-3);return;}if(key=="BaseColor"){Palette(-4);return;}
   if(StringFind(key,"On")==0 && key!="OnlySource")
     {int i=(int)StringToInteger(StringSubstr(key,2));if(i>=0 && i<g_edit.count)g_edit.levels[i].enabled=!g_edit.levels[i].enabled;}
   else if(StringFind(key,"Remove")==0)
     {int i=(int)StringToInteger(StringSubstr(key,6));if(i>=0 && i<g_edit.count){for(int k=i;k<g_edit.count-1;k++)g_edit.levels[k]=g_edit.levels[k+1];g_edit.count--;g_page=Lim(g_page,0,(int)MathMax(0,(g_edit.count-1)/g_rows));}}
   else if(key=="Add")
     {if(g_edit.count<FP_MAX_LEVELS){int i=g_edit.count++;DefaultLevel(g_edit.levels[i],.75);g_edit.levels[i].ink=FPTierColor(g_edit.source_tf);g_edit.levels[i].width=FPTierWidth(g_edit.source_tf);g_page=i/g_rows;}}
   else if(key=="Defaults"){FPResetLevels(g_edit);g_page=0;}
   else if(key=="Sort"){FPSortLevels(g_edit,g_level_desc);g_level_desc=!g_level_desc;g_page=0;}
   else if(StringFind(key,"Group")==0)FPToggleGroup(g_edit,Lim((int)StringToInteger(StringSubstr(key,5)),1,3));
   else if(key=="Used")MarkUsed(g_edit,!g_edit.used);
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

// ------------------------------------------------------------------ lot size & risk (1.66)
// Press on the chart and drag to the stop: the box shows the volume whose loss at the stop
// matches the risk per trade. The value of a price move per lot comes from your own value,
// the calibration script, or the contract size cross-checked with the broker's tick value.
// ---- pure calculation (also exercised by the local tests)
// Decimal places of a volume step: 0.01 -> 2, 0.1 -> 1, 1 -> 0, 0.05 -> 2.
int FPLotDigits(const double step)
  {
   int d=0;double s=step;
   while(d<8 && MathAbs(s-MathRound(s))>1e-7*MathMax(1.0,MathAbs(s))){s*=10;d++;}
   return d;
  }
// Volume whose loss at the stop is at most `risk` (account currency). dist: price distance
// from entry to stop; value: account currency per 1.0 price move per 1.00 lot; commission:
// per 1.00 lot, round turn. Rounded DOWN to the volume step. flag: 0 ok, 1 below the minimum
// volume (returns 0), 2 capped at the maximum volume, -1 nothing to size.
double FPRiskLots(const double risk,const double dist,const double value,const double commission,const double vmin,const double vmax,const double step,int &flag)
  {
   flag=-1;
   if(!(risk>0) || !(dist>0) || !(value>0) || !(step>0))return 0;
   double per_lot=dist*value+MathMax(0.0,commission);
   int digits=FPLotDigits(step);
   double lots=NormalizeDouble(MathFloor(risk/per_lot/step+1e-7)*step,digits);
   flag=0;
   if(lots<=0 || (vmin>0 && lots<vmin-step*1e-6)){flag=1;return 0;}
   if(vmax>0 && lots>vmax){flag=2;lots=NormalizeDouble(MathFloor(vmax/step+1e-7)*step,digits);}
   return lots;
  }
// Risk per trade in the account currency.
double FPRiskAmount(const int mode,const double amount,const double percent,const double base,const double balance,const double equity)
  {
   if(mode==0)return MathMax(0.0,amount);
   double of=mode==1?balance:(mode==2?equity:base);
   return MathMax(0.0,of)*MathMax(0.0,percent)/100.0;
  }
// 1 long, -1 short, 0 invalid. At market a long's stop must be below the bid and a short's
// above the ask (a stop inside the spread would be hit at once).
int FPRiskSide(const bool market,const double entry,const double stop,const double bid,const double ask)
  {
   if(market)
     {
      if(!(bid>0) || !(ask>0))return 0;
      return stop<bid?1:(stop>ask?-1:0);
     }
   return stop<entry?1:(stop>entry?-1:0);
  }
// Entry: the live ask for a buy and bid for a sell at market, otherwise the chosen price.
double FPRiskEntry(const bool market,const int side,const double entry,const double bid,const double ask)
  {return market?(side>0?ask:(side<0?bid:(bid+ask)*0.5)):entry;}
// Target r R away from the entry on the profit side, and the R of a target price.
double FPTargetPrice(const double entry,const double stop,const double r){return entry+(entry-stop)*r;}
double FPTargetR(const double entry,const double stop,const double tp)
  {double d=entry-stop;return d!=0?(tp-entry)/d:0;}
// A price on the symbol's tick grid (no OHLC magnet: the price stays where you put it).
double FPNormTick(const double price,const double tick,const int digits)
  {return tick>0?NormalizeDouble(MathRound(price/tick)*tick,digits):NormalizeDouble(price,digits);}
// "2", "1 2 3", "1.5, 3" or "2;4": R multiples above 0 and up to 100, sorted, without
// repeats, at most `cap`. Returns the count, 0 for an empty text, -1 for anything else.
int FPParseRList(string text,double &out[],const int cap)
  {
   StringReplace(text,","," ");StringReplace(text,";"," ");
   string parts[];
   int n=StringSplit(text,' ',parts),count=0;
   ArrayResize(out,cap);
   for(int i=0;i<n;i++)
     {
      string t=parts[i];StringTrimLeft(t);StringTrimRight(t);
      if(StringLen(t)==0)continue;
      if(!Numeric(t))return -1;
      double r=NormalizeDouble(StringToDouble(t),2);
      if(!(r>0) || r>100)return -1;
      bool seen=false;
      for(int k=0;k<count;k++)if(MathAbs(out[k]-r)<1e-9)seen=true;
      if(!seen && count<cap)out[count++]=r;
     }
   for(int i=1;i<count;i++){double v=out[i];int j=i;while(j>0 && out[j-1]>v){out[j]=out[j-1];j--;}out[j]=v;}
   return count;
  }
// 2 -> "2", 1.5 -> "1.5", 0.25 -> "0.25"
string FPRNum(const double r)
  {
   string s=DoubleToString(r,2);
   while(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)=="0")s=StringSubstr(s,0,StringLen(s)-1);
   if(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)==".")s=StringSubstr(s,0,StringLen(s)-1);
   return s;
  }
string FPRListText(double &r[],const int n)
  {string s="";for(int i=0;i<n;i++){if(i>0)s+=" ";s+=FPRNum(r[i]);}return s;}
// Up to six decimals, without trailing zeros: 100 -> "100", 0.0125 -> "0.0125".
string RiskNumText(const double v)
  {
   string s=DoubleToString(v,6);
   while(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)=="0")s=StringSubstr(s,0,StringLen(s)-1);
   if(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)==".")s=StringSubstr(s,0,StringLen(s)-1);
   return s;
  }
// 12345.678 -> "12,345.68"
string FPMoney(const double v)
  {
   string s=DoubleToString(MathAbs(v),2);
   int dot=StringFind(s,".");
   string head=dot>=0?StringSubstr(s,0,dot):s,tail=dot>=0?StringSubstr(s,dot):"",out="";
   int n=StringLen(head);
   for(int i=0;i<n;i++){out+=StringSubstr(head,i,1);int left=n-1-i;if(left>0 && left%3==0)out+=",";}
   return (v<=-0.005?"-":"")+out+tail;
  }
// Which value sizes the trade: your own value, then the calibration, then the contract size
// and the tick value when they agree (the larger, so the volume errs small). Two methods
// that disagree by more than 2% block the size until you calibrate or set a value.
int FPValueDecide(const double manual,const double calib,const double contract,const double tick,double &value,bool &disagree)
  {
   value=0;
   disagree=contract>0 && tick>0 && MathAbs(contract-tick)>FPC_TOL*MathMax(contract,tick);
   if(manual>0){value=manual;return 1;}
   if(calib>0){value=calib;return 2;}
   if(disagree)return 0;
   if(contract>0 && tick>0){value=MathMax(contract,tick);return 3;}
   if(contract>0){value=contract;return 4;}
   if(tick>0){value=tick;return 5;}
   return 0;
  }
bool FPIsFiat(const string c)
  {
   string list="USD EUR GBP JPY CHF AUD NZD CAD SEK NOK DKK SGD HKD ZAR MXN PLN TRY CNH HUF CZK ILS";
   return StringLen(c)==3 && StringFind(list,c)>=0;
  }
// The pending order a chosen entry needs: a buy below the ask is a limit, above it a stop.
string FPPendingName(const int side,const double entry,const double bid,const double ask)
  {
   if(side>0)return ask>0 && entry>ask?"BUY STOP":"BUY LIMIT";
   if(side<0)return bid>0 && entry<bid?"SELL STOP":"SELL LIMIT";
   return "";
  }

// ---- settings: one file per account, shared by every chart and workspace of that account
void FPRDefaults(FPRiskConfig &c)
  {
   c.mode=1;c.amount=100;c.percent=1;c.base=10000;c.entry=0;c.targets="2";c.add_r="3";c.count=0;
   for(int i=0;i<FPR_MAX_SYMS;i++){c.syms[i].symbol="";c.syms[i].commission=0;c.syms[i].value=0;}
  }
void FPRWriteConfig(const int f,FPRiskConfig &c)
  {
   FileWriteInteger(f,FPR_MAGIC);FileWriteInteger(f,FPR_SCHEMA);
   FileWriteInteger(f,c.mode);FileWriteDouble(f,c.amount);FileWriteDouble(f,c.percent);FileWriteDouble(f,c.base);
   FileWriteInteger(f,c.entry);WText(f,c.targets);WText(f,c.add_r);
   FileWriteInteger(f,c.count);
   for(int i=0;i<c.count;i++){WText(f,c.syms[i].symbol);FileWriteDouble(f,c.syms[i].commission);FileWriteDouble(f,c.syms[i].value);}
   FileWriteInteger(f,FPR_END);
  }
bool FPRReadConfig(const int f,FPRiskConfig &c)
  {
   if(FileReadInteger(f)!=FPR_MAGIC || FileReadInteger(f)!=FPR_SCHEMA)return false;
   c.mode=FileReadInteger(f);c.amount=FileReadDouble(f);c.percent=FileReadDouble(f);c.base=FileReadDouble(f);
   c.entry=FileReadInteger(f);
   if(!RText(f,c.targets,200) || !RText(f,c.add_r,200))return false;
   c.count=FileReadInteger(f);
   if(c.mode<0 || c.mode>3 || c.entry<0 || c.entry>1 || c.count<0 || c.count>FPR_MAX_SYMS)return false;
   if(!MathIsValidNumber(c.amount) || !MathIsValidNumber(c.percent) || !MathIsValidNumber(c.base) || c.amount<0 || c.percent<0 || c.percent>100 || c.base<0)return false;
   for(int i=0;i<c.count;i++)
     {
      if(!RText(f,c.syms[i].symbol,64))return false;
      c.syms[i].commission=FileReadDouble(f);c.syms[i].value=FileReadDouble(f);
      if(!MathIsValidNumber(c.syms[i].commission) || !MathIsValidNumber(c.syms[i].value) || c.syms[i].commission<0 || c.syms[i].value<0)return false;
     }
   return FileReadInteger(f)==FPR_END;
  }
bool FPRReadFile(const string filename,FPRiskConfig &c)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   FPRiskConfig candidate;FPRDefaults(candidate);
   bool good=FPRReadConfig(f,candidate) && FileTell(f)==FileSize(f);
   FileClose(f);
   if(good)c=candidate;
   return good;
  }
// Written to a temporary file, verified by reading it back, then swapped in (old copy kept as .bak).
bool FPRWriteFile(const string filename,FPRiskConfig &c)
  {
   string temporary=filename+".tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();FPRWriteConfig(f,c);FileFlush(f);int error=GetLastError();FileClose(f);
   FPRiskConfig check;FPRDefaults(check);
   if(error!=0 || !FPRReadFile(temporary,check) || check.count!=c.count || check.mode!=c.mode || check.targets!=c.targets)return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }
int FPRSymFind(FPRiskConfig &c,const string symbol)
  {for(int i=0;i<c.count;i++)if(c.syms[i].symbol==symbol)return i;return -1;}
double FPRCommission(FPRiskConfig &c,const string symbol){int i=FPRSymFind(c,symbol);return i>=0?c.syms[i].commission:0;}
double FPRManual(FPRiskConfig &c,const string symbol){int i=FPRSymFind(c,symbol);return i>=0?c.syms[i].value:0;}
// A symbol with no commission and no value of its own leaves the table; false when it is full.
bool FPRSymSet(FPRiskConfig &c,const string symbol,const double commission,const double value)
  {
   int i=FPRSymFind(c,symbol);
   if(!(commission>0) && !(value>0))
     {
      if(i>=0){for(int k=i;k<c.count-1;k++)c.syms[k]=c.syms[k+1];c.count--;}
      return true;
     }
   if(i<0){if(c.count>=FPR_MAX_SYMS)return false;i=c.count++;c.syms[i].symbol=symbol;}
   c.syms[i].commission=commission>0?commission:0;c.syms[i].value=value>0?value:0;
   return true;
  }
bool SaveRisk()
  {
   if(g_rstore=="" || !g_owner)return false;
   if(!FPRWriteFile(g_rstore,g_rcfg)){Print("Fibonacci Pro: could not save risk settings, error ",GetLastError());return false;}
   g_rstore_mtime=(datetime)FileGetInteger(g_rstore,FILE_MODIFY_DATE);g_rstore_found=true;
   return true;
  }
void LoadRisk()
  {
   FPRDefaults(g_rcfg);
   g_rstore_found=FPRReadFile(g_rstore,g_rcfg) || FPRReadFile(g_rstore+".bak",g_rcfg);
   g_rstore_mtime=FileIsExist(g_rstore)?(datetime)FileGetInteger(g_rstore,FILE_MODIFY_DATE):0;
   g_redit=g_rcfg;RiskReset();
  }
// Another chart of the same account saved new settings.
void RiskPollShared()
  {
   if(g_reditor || g_rstore=="" || !FileIsExist(g_rstore))return;
   datetime m=(datetime)FileGetInteger(g_rstore,FILE_MODIFY_DATE);
   if(m<=0 || m==g_rstore_mtime)return;
   FPRiskConfig loaded;FPRDefaults(loaded);
   if(!FPRReadFile(g_rstore,loaded))return;
   g_rcfg=loaded;g_rstore_mtime=m;g_rstore_found=true;g_dirty=true;g_ui_dirty=true;
  }

// ---- this chart's symbol: properties and the value of a 1.0 price move per 1.00 lot
void RiskRefreshInfo()
  {
   g_rsym.profit_ccy=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   g_rsym.account_ccy=AccountInfoString(ACCOUNT_CURRENCY);
   g_rsym.contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   g_rsym.point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(!(g_rsym.point>0))g_rsym.point=_Point;
   g_rsym.tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(!(g_rsym.tick_size>0))g_rsym.tick_size=g_rsym.point;
   g_rsym.vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   g_rsym.vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   g_rsym.vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(!(g_rsym.vstep>0))g_rsym.vstep=g_rsym.vmin>0?g_rsym.vmin:0.01;
   g_rsym.digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   g_rsym.calc_mode=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
   string base=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
   g_rsym.fx=g_rsym.calc_mode==SYMBOL_CALC_MODE_FOREX || g_rsym.calc_mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE
             || (base!=g_rsym.profit_ccy && FPIsFiat(base) && FPIsFiat(g_rsym.profit_ccy));
  }
void RiskLoadCalibration(const bool force)
  {
   string file=FPCFile();
   bool exists=FileIsExist(file);
   datetime m=exists?(datetime)FileGetInteger(file,FILE_MODIFY_DATE):0;
   if(!force && g_rcal_checked && m==g_rcal_mtime)return;
   g_rcal_checked=true;g_rcal_mtime=m;g_rcal_found=false;
   if(!exists)return;
   FPCalib list[];
   int n=FPCLoad(file,list);
   int i=n>0?FPCFind(list,n,_Symbol):-1;
   if(i>=0){g_rcal=list[i];g_rcal_found=true;}
  }
// The calibrated value in the account currency at today's rate (0: none, or voided because
// the contract size changed since the calibration).
double RiskCalibValue(bool &stale)
  {
   stale=false;
   if(!g_rcal_found)return 0;
   if(MathAbs(g_rcal.contract-g_rsym.contract)>1e-9*MathMax(1.0,MathAbs(g_rsym.contract))){stale=true;return 0;}
   if(g_rcal.value_profit>0)
     {
      double conv=FPCConv(g_rcal.profit_ccy,g_rsym.account_ccy,g_rconv_key,g_rconv_sym,g_rconv_inv);
      if(conv>0)return g_rcal.value_profit*conv;
     }
   return g_rcal.account_ccy==g_rsym.account_ccy?g_rcal.value_account:0;
  }
// Each method's value; which one sizes the trade is decided per frame (FPValueDecide).
void RiskRefreshValue()
  {
   RiskRefreshInfo();
   RiskLoadCalibration(false);
   g_rval.contract=FPCContractValue(_Symbol,g_rsym.account_ccy,g_rconv_key,g_rconv_sym,g_rconv_inv);
   g_rval.tick=FPCTickValue(_Symbol);
   g_rval.calib=RiskCalibValue(g_rval.calib_stale);
  }
double RiskNorm(const double p){return FPNormTick(p,g_rsym.tick_size,_Digits);}
double RiskPip(){return g_rsym.point*((g_rsym.digits==3 || g_rsym.digits==5)?10:1);}
// Values and distances are shown per pip on forex and per 1.0 price move elsewhere.
double RiskUnit(){return g_rsym.fx?RiskPip():1.0;}
string RiskUnitText(){return g_rsym.fx?"per pip ("+DoubleToString(RiskPip(),g_rsym.digits)+")":"per 1.0 move";}
// A distance as a loss (-) or gain (+): pips on forex, the price difference elsewhere.
string RiskMoveText(const double move)
  {
   string sign=move>0?"+":(move<0?"-":"");
   double a=MathAbs(move);
   if(g_rsym.fx)return sign+DoubleToString(a/RiskPip(),1)+" pips";
   return sign+DoubleToString(a,g_rsym.digits);
  }
string RiskLotText(const double lots){return DoubleToString(lots,FPLotDigits(g_rsym.vstep));}
string RiskSourceText(const int source)
  {
   if(source==1)return "your own value";
   if(source==2)return "calibrated";
   if(source==3)return "contract size and tick value agree";
   if(source==4)return "contract size only";
   if(source==5)return "tick value only";
   return "none";
  }

// ---- the measurement
void RiskReset()
  {
   g_risk.armed=false;g_risk.active=false;g_risk.stage=0;g_risk.market=g_rcfg.entry==0;
   g_risk.t0=0;g_risk.entry=0;g_risk.stop=0;g_risk.ntp=0;
   for(int k=0;k<FPR_MAX_TP;k++){g_risk.tp[k]=0;g_risk.tp_r[k]=0;g_risk.tp_fixed[k]=true;}
   g_rdrag=0;g_rcreating=false;g_rdrag_moved=false;g_rgok=false;
  }
void RiskInitTargets()
  {
   double r[];
   int n=FPParseRList(g_reditor?g_redit.targets:g_rcfg.targets,r,FPR_MAX_TP);
   g_risk.ntp=0;
   for(int i=0;i<n;i++){int k=g_risk.ntp++;g_risk.tp_r[k]=r[i];g_risk.tp_fixed[k]=true;g_risk.tp[k]=0;}
  }
// Start a new measurement (it replaces the previous one).
void RiskArm()
  {
   if(g_drag!=0 || g_armed || g_toolbar_drag)CancelDrag();
   if(g_editor)CloseEditor();
   ClosePopup();
   RiskReset();
   g_risk.armed=true;
   g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
   HoldScroll();
   // Another program may have switched mouse-move events off; the crosshair needs them.
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   g_ui_dirty=true;g_dirty=true;
   // Until settings are saved, the first measurement of a session opens the Risk window once.
   if(!g_rstore_found && !g_rintro && !g_reditor && !g_zeditor)
     {g_rintro=true;OpenRisk();Status("First check your risk per trade here. Then press on the chart and drag to your stop.");return;}
   Status(g_risk.market?"Press on the chart and drag to your stop (or click it). Entry: market. Esc cancels."
                       :"Press at your entry price and drag to your stop. Esc cancels.");
  }
void RiskClear()
  {
   bool had=g_risk.armed || g_risk.active;
   RiskReset();
   g_dirty=true;g_ui_dirty=true;
   if(had)Status("Risk measurement removed.");
  }
// Toolbar button and hotkey: a new measurement, or cancel the one being made.
void RiskButton(){if(g_risk.armed)RiskClear();else RiskArm();}
// Esc: a dragged line goes back; a measurement being made is dropped.
void RiskCancel()
  {
   if(g_rdrag!=0 && !g_rcreating){g_risk=g_risk_backup;g_rdrag=0;g_rdrag_moved=false;g_dirty=true;Status("Change canceled.");return;}
   RiskClear();
  }
// Screen geometry of the box for this frame (also used by hit-testing).
void RiskGeometry()
  {
   g_rgok=false;g_rgfar=FP_OFF;
   for(int k=0;k<FPR_MAX_TP;k++)g_rgty[k]=FP_OFF;
   if(!g_risk.active)return;
   int ignore=0;
   if(!XY(g_risk.t0,g_rview.stop,g_rgx0,g_rgys) || !XY(g_risk.t0,g_rview.entry,ignore,g_rgye))return;
   for(int k=0;k<g_rview.ntp;k++)
     {
      if(!(g_rview.tp[k]>0) || !XY(g_risk.t0,g_rview.tp[k],ignore,g_rgty[k])){g_rgty[k]=FP_OFF;continue;}
      if(g_rview.tp_r[k]>0 && (g_rgfar==FP_OFF || MathAbs(g_rgty[k]-g_rgye)>MathAbs(g_rgfar-g_rgye)))g_rgfar=g_rgty[k];
     }
   g_rgok=true;
  }
// 1 stop, 2 entry (chosen-price entry only), 10+k target k, 0 nothing.
int RiskHit(const int x,const int y)
  {
   if(!g_risk.active || g_risk.armed)return 0;
   RiskGeometry();
   if(!g_rgok || x<MathMax(0,g_rgx0)-U(4))return 0;
   int tol=U(5);
   if(MathAbs(y-g_rgys)<=tol)return 1;
   for(int k=g_rview.ntp-1;k>=0;k--)if(g_rgty[k]!=FP_OFF && MathAbs(y-g_rgty[k])<=tol)return 10+k;
   if(!g_risk.market && MathAbs(y-g_rgye)<=tol)return 2;
   return 0;
  }
void RiskRemoveTargetAt(const int k)
  {
   if(k<0 || k>=g_risk.ntp)return;
   for(int i=k;i<g_risk.ntp-1;i++){g_risk.tp[i]=g_risk.tp[i+1];g_risk.tp_r[i]=g_risk.tp_r[i+1];g_risk.tp_fixed[i]=g_risk.tp_fixed[i+1];}
   g_risk.ntp--;g_risk.tp[g_risk.ntp]=0;g_risk.tp_r[g_risk.ntp]=0;g_risk.tp_fixed[g_risk.ntp]=true;
   g_dirty=true;
  }
// Chart press: makes the measurement while armed, or grabs one of its lines.
bool RiskPress(const int x,const int y)
  {
   if(!g_risk.armed && !g_risk.active)return false;
   if(g_armed)return false;   // New Fib is armed: the press starts the Fib, even on a risk line
   datetime t=0;double p=0;
   if(g_risk.armed)
     {
      if(!Point(x,y,t,p)){Status("Choose a point inside the main chart window.");return true;}
      p=RiskNorm(p);
      g_rpress_stage=g_risk.stage;
      if(!g_risk.active)
        {
         // The first press starts the box. At market it places the stop, otherwise the entry.
         g_risk.active=true;g_risk.t0=t;RiskInitTargets();
         if(!g_risk.market){g_risk.entry=p;g_risk.stage=1;}
        }
      g_risk.stop=p;
      g_rdrag=1;g_rcreating=true;g_rdrag_px=x;g_rdrag_py=y;g_rdrag_moved=false;
      HoldScroll();g_dirty=true;return true;
     }
   int hit=RiskHit(x,y);
   if(hit==0)return false;
   ulong now=GetTickCount64();
   // Double-click a target line to remove that target.
   if(hit>=10 && hit==g_rlast_hit && now-g_rlast_down<400){g_rlast_down=0;RiskRemoveTargetAt(hit-10);Status("Target removed.");return true;}
   g_rlast_hit=hit;g_rlast_down=now;
   g_risk_backup=g_risk;
   g_rdrag=hit;g_rcreating=false;g_rdrag_px=x;g_rdrag_py=y;g_rdrag_moved=false;
   HoldScroll();return true;
  }
void RiskMove(const int x,const int y)
  {
   if(g_rdrag==0)return;
   // A press becomes a drag after 3 px, so a plain click moves nothing.
   if(!g_rdrag_moved && MathAbs(x-g_rdrag_px)+MathAbs(y-g_rdrag_py)<3)return;
   g_rdrag_moved=true;
   datetime t=0;double p=0;
   if(!Point(x,y,t,p))return;
   p=RiskNorm(p);
   if(g_rdrag==1)g_risk.stop=p;
   else if(g_rdrag==2)g_risk.entry=p;
   else if(g_rdrag>=10 && g_rdrag-10<g_risk.ntp){int k=g_rdrag-10;g_risk.tp[k]=p;g_risk.tp_fixed[k]=false;}
   g_dirty=true;
  }
string RiskSummary()
  {
   if(g_rview.side==0)return "Move the stop away from the entry.";
   if(g_rview.flag==0 || g_rview.flag==2)
      return (g_rview.side>0?"Buy ":"Sell ")+RiskLotText(g_rview.lots)+" lots: "+FPMoney(g_rview.actual)+" "+g_rsym.account_ccy+" lost at the stop. Drag the lines to adjust; Esc removes it.";
   return "No lot size: "+g_rview.why+".";
  }
void RiskRelease()
  {
   if(g_rdrag==0)return;
   bool creating=g_rcreating,moved=g_rdrag_moved;
   g_rdrag=0;g_rcreating=false;g_rdrag_moved=false;g_dirty=true;
   if(!creating){if(moved){RiskPrepare();Status(RiskSummary());}return;}
   // A chosen-price entry placed with a click: the stop follows the pointer until the next click.
   if(!g_risk.market && g_rpress_stage==0 && !moved)
     {Status("Entry "+DoubleToString(g_risk.entry,_Digits)+" placed. Now click your stop. Esc cancels.");return;}
   RiskPrepare();
   if(g_rview.side==0)
     {
      if(g_risk.market){g_risk.active=false;Status("The stop must be outside the spread. Click your stop again, or Esc.");}
      else Status("The stop must differ from the entry. Click your stop, or Esc.");
      return;
     }
   g_risk.armed=false;g_risk.stage=0;g_ui_dirty=true;
   Status(RiskSummary());
  }
// Pointer moves with no button pressed: the crosshair, or the stop following the pointer.
void RiskHover(const int x,const int y)
  {
   if(!g_risk.armed || g_rdrag!=0)return;
   if(g_risk.active && g_risk.stage==1)
     {datetime t=0;double p=0;if(Point(x,y,t,p))g_risk.stop=RiskNorm(p);}
   g_dirty=true;
  }
void RiskAddTargets()
  {
   if(!g_risk.active || g_risk.armed){Status("Make a measurement first: press on the chart and drag to your stop.");return;}
   double r[];
   int n=FPParseRList(g_rcfg.add_r,r,FPR_MAX_TP),added=0,repeated=0;
   if(n<=0){Status("Type the R multiples to add, e.g. 3 or 1.5 3 5.");return;}
   bool full=false;
   for(int i=0;i<n;i++)
     {
      bool seen=false;
      for(int k=0;k<g_risk.ntp;k++)if(g_risk.tp_fixed[k] && MathAbs(g_risk.tp_r[k]-r[i])<1e-9)seen=true;
      if(seen){repeated++;continue;}
      if(g_risk.ntp>=FPR_MAX_TP){full=true;break;}
      int k=g_risk.ntp++;g_risk.tp_r[k]=r[i];g_risk.tp_fixed[k]=true;g_risk.tp[k]=0;added++;
     }
   g_dirty=true;
   if(full)Status("At most "+IntegerToString(FPR_MAX_TP)+" targets; "+IntegerToString(added)+" added.");
   else if(added>0)Status("Added "+IntegerToString(added)+" target(s). Drag a target to move it; double-click one to remove it.");
   else if(repeated>0)Status("Those targets are already on the chart.");
  }
void RiskRemoveFarthest()
  {
   if(!g_risk.active || g_risk.ntp==0){Status("No target to remove.");return;}
   int farthest=0;
   for(int k=1;k<g_risk.ntp && k<g_rview.ntp;k++)if(MathAbs(g_rview.tp_r[k])>MathAbs(g_rview.tp_r[farthest]))farthest=k;
   RiskRemoveTargetAt(farthest);
   Status("Farthest target removed. Double-click a target line to remove that one.");
  }
// Market <-> chosen price for the measurement on the chart. To a chosen price, the entry
// stays where the market is now.
void RiskModeSwitch(const bool market)
  {
   if(g_risk.market==market)return;
   if(g_risk.active && !market)
     {
      RiskPrepare();
      g_risk.entry=g_rview.side!=0?g_rview.entry:RiskNorm((g_rlast_bid+g_rlast_ask)*0.5);
     }
   g_risk.market=market;
   if(g_risk.armed && !g_risk.active)g_risk.stage=0;
   g_dirty=true;
  }
void RiskSetMarket(const bool market)
  {
   RiskModeSwitch(market);
   int entry=market?0:1;
   if(g_rcfg.entry!=entry){g_rcfg.entry=entry;SaveRisk();}
   if(g_reditor)g_redit.entry=entry;
   g_ui_dirty=true;
   Status(market?"Entry at the market price: the ask for a buy, the bid for a sell.":"Entry at a price you choose: press at the entry, drag to the stop (limit or stop order).");
  }
// Prices, size and labels from live quotes, the account and the symbol value.
void RiskComputeWith(FPRiskConfig &c)
  {
   FPRiskView v;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   g_rlast_bid=bid;g_rlast_ask=ask;
   g_rlast_bal=AccountInfoDouble(ACCOUNT_BALANCE);g_rlast_eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double value=0;bool disagree=false;
   g_rval.source=FPValueDecide(FPRManual(c,_Symbol),g_rval.calib,g_rval.contract,g_rval.tick,value,disagree);
   g_rval.value=value;g_rval.disagree=disagree;
   v.risk=FPRiskAmount(c.mode,c.amount,c.percent,c.base,g_rlast_bal,g_rlast_eq);
   v.side=FPRiskSide(g_risk.market,g_risk.entry,g_risk.stop,bid,ask);
   v.entry=FPRiskEntry(g_risk.market,v.side,g_risk.entry,bid,ask);
   v.stop=g_risk.stop;
   v.dist=MathAbs(v.entry-v.stop);
   v.commission=FPRCommission(c,_Symbol);
   v.per_lot=v.dist*value+v.commission;
   v.lots=0;v.actual=0;v.flag=-1;v.why="";
   v.min_risk=g_rsym.vmin*v.per_lot;
   if(v.side==0)v.why=g_risk.market?((bid>0 && ask>0)?"stop inside the spread":"no quotes"):"stop at the entry";
   else if(!(value>0))v.why=disagree?"contract size and tick value disagree (see the Risk window)":"symbol value unknown (see the Risk window)";
   else
     {
      v.lots=FPRiskLots(v.risk,v.dist,value,v.commission,g_rsym.vmin,g_rsym.vmax,g_rsym.vstep,v.flag);
      v.actual=v.lots*v.per_lot;
      if(v.flag==1)v.why="below the minimum volume";
      else if(v.flag<0)v.why="no risk amount set";
     }
   v.ntp=g_risk.ntp;
   for(int k=0;k<FPR_MAX_TP;k++){v.tp[k]=0;v.tp_r[k]=0;}
   for(int k=0;k<g_risk.ntp;k++)
     {
      if(g_risk.tp_fixed[k]){v.tp_r[k]=g_risk.tp_r[k];v.tp[k]=v.side!=0?RiskNorm(FPTargetPrice(v.entry,v.stop,g_risk.tp_r[k])):0;}
      else {v.tp[k]=g_risk.tp[k];v.tp_r[k]=v.side!=0?FPTargetR(v.entry,v.stop,g_risk.tp[k]):0;}
     }
   g_rview=v;
  }
// Once per frame before drawing. While the crosshair waits, the pointer is the stop (market)
// or the entry (chosen price), so its readout shows the size before you press.
void RiskPrepare()
  {
   if(!g_risk.armed && !g_risk.active){g_rgok=false;return;}
   if(g_risk.armed && !g_risk.active && g_mouse_in)
     {
      datetime t=0;double p=0;
      if(Point(g_mouse_x,g_mouse_y,t,p)){g_risk.stop=RiskNorm(p);if(!g_risk.market)g_risk.entry=g_risk.stop;}
     }
   if(g_reditor)RiskComputeWith(g_redit);else RiskComputeWith(g_rcfg);
   RiskGeometry();
  }

// ---- drawing: red loss and green profit areas behind the candles, lines and tags in front
int RiskShade(FPLayer &layers[],const int n)
  {
   if(!g_rgok || g_rview.side==0 || g_rgx0>=g_width)return n;
   int l=(int)MathMax(0,g_rgx0),r=g_width-1,m=n;
   FPLayerSet(layers[m],l,r,(int)MathMin(g_rgye,g_rgys),(int)MathMax(g_rgye,g_rgys),FPR_LOSS,FPR_LOSS,.16,.16,2);m++;
   if(g_rgfar!=FP_OFF){FPLayerSet(layers[m],l,r,(int)MathMin(g_rgye,g_rgfar),(int)MathMax(g_rgye,g_rgfar),FPR_PROFIT,FPR_PROFIT,.13,.13,2);m++;}
   return m;
  }
ulong RiskFillSig(ulong hash)
  {
   if(!g_rgok || g_rview.side==0)return FPMix(hash,0);
   return FPMix(FPMix(FPMix(FPMix(FPMix(hash,1),g_rgx0),g_rgye),g_rgys),g_rgfar);
  }
string RiskPctText(const double amount)
  {
   int mode=g_reditor?g_redit.mode:g_rcfg.mode;
   double base=g_reditor?g_redit.base:g_rcfg.base;
   double of=mode==2?g_rlast_eq:(mode==3?base:g_rlast_bal);
   if(!(of>0))return "-";
   return DoubleToString(amount/of*100.0,2)+"%";
  }
string RiskEntryText()
  {
   string price=DoubleToString(g_rview.entry,_Digits);
   if(g_rview.side==0)return (g_risk.market?"Market ":"Entry ")+price+": "+g_rview.why;
   string order=g_risk.market?(g_rview.side>0?"BUY":"SELL"):FPPendingName(g_rview.side,g_rview.entry,g_rlast_bid,g_rlast_ask);
   string where=g_risk.market?" at market ":" @ ";
   if(g_rview.flag==0 || g_rview.flag==2)
      return order+" "+RiskLotText(g_rview.lots)+" lots"+where+price+(g_rview.flag==2?" (maximum volume)":"");
   if(g_rview.flag==1)
      return order+where+price+": below "+RiskLotText(g_rsym.vmin)+" lot ("+RiskLotText(g_rsym.vmin)+" loses "+FPMoney(g_rview.min_risk)+" "+g_rsym.account_ccy+")";
   return order+where+price+": no size, "+g_rview.why;
  }
string RiskStopText()
  {
   string s="SL "+DoubleToString(g_rview.stop,_Digits);
   if(g_rview.side==0)return s;
   s+="  "+RiskMoveText(-g_rview.dist);
   if(g_rview.flag==0 || g_rview.flag==2)s+="  -"+FPMoney(g_rview.actual)+" "+g_rsym.account_ccy+" ("+RiskPctText(g_rview.actual)+")";
   else s+="  risk "+FPMoney(g_rview.risk)+" "+g_rsym.account_ccy;
   return s;
  }
string RiskTargetText(const int number,const int k)
  {
   double move=g_rview.side*(g_rview.tp[k]-g_rview.entry);
   string s="TP"+IntegerToString(number)+"  "+FPRNum(NormalizeDouble(g_rview.tp_r[k],g_risk.tp_fixed[k]?2:1))+"R  "+DoubleToString(g_rview.tp[k],_Digits)+"  "+RiskMoveText(move);
   if(g_rview.flag==0 || g_rview.flag==2)
     {
      double profit=g_rview.lots*(move*g_rval.value-g_rview.commission);
      string sign=profit>=0?"+":"-";
      s+="  "+sign+FPMoney(MathAbs(profit))+" "+g_rsym.account_ccy;
     }
   return s;
  }
// A price tag at the right edge: text on a filled box, centred on y.
void RiskTag(const int xr,const int yc,const string text,const color bg,const color ink)
  {
   int tw=g_line_canvas.TextWidth(text),th=g_line_canvas.TextHeight(text);
   int x1=Lim(xr,0,g_width-1),x0=(int)MathMax(0,x1-tw-U(10));
   int y0=Lim(yc-th/2-U(2),0,(int)MathMax(0,g_height-th-U(5))),y1=Lim(y0+th+U(3),0,g_height-1);
   g_line_canvas.FillRectangle(x0,y0,x1,y1,ColorToARGB(bg,235));
   g_line_canvas.TextOut(x0+U(5),y0+U(2),text,ColorToARGB(ink));
  }
void RiskAddTag(const int y,const string text,const color bg,const color ink)
  {
   if(g_rtag_n>=FPR_MAX_TP+2)return;
   g_rtags[g_rtag_n].y=y;g_rtags[g_rtag_n].pos=y;g_rtags[g_rtag_n].text=text;g_rtags[g_rtag_n].bg=bg;g_rtags[g_rtag_n].ink=ink;
   g_rtag_n++;
  }
// Tags of lines closer than a tag's height are pushed apart, top to bottom.
void RiskDrawTags(const int xr)
  {
   int h=g_line_canvas.TextHeight("Ag")+U(5);
   int order[FPR_MAX_TP+2];
   for(int i=0;i<g_rtag_n;i++)order[i]=i;
   for(int i=1;i<g_rtag_n;i++){int v=order[i],j=i;while(j>0 && g_rtags[order[j-1]].y>g_rtags[v].y){order[j]=order[j-1];j--;}order[j]=v;}
   for(int q=1;q<g_rtag_n;q++)
     {int i=order[q],prev=order[q-1];if(g_rtags[i].pos<g_rtags[prev].pos+h)g_rtags[i].pos=g_rtags[prev].pos+h;}
   for(int i=0;i<g_rtag_n;i++)RiskTag(xr,g_rtags[i].pos,g_rtags[i].text,g_rtags[i].bg,g_rtags[i].ink);
  }
void RiskDraw()
  {
   g_rtag_n=0;
   if(!g_rgok || g_rgx0>=g_width)return;
   int l=(int)MathMax(0,g_rgx0),r=g_width-1;
   // A market entry follows the price (dashed); a chosen entry is solid. A grabbed line is thicker.
   HLine(l,r,g_rgye,g_chart_fg,g_rdrag==2?2:1,g_risk.market?STYLE_DASH:STYLE_SOLID);
   HLine(l,r,g_rgys,FPR_LOSS,g_rdrag==1?2:1,STYLE_SOLID);
   for(int k=0;k<g_rview.ntp;k++)if(g_rgty[k]!=FP_OFF)HLine(l,r,g_rgty[k],FPR_PROFIT,g_rdrag==10+k?2:1,STYLE_SOLID);
   RiskAddTag(g_rgye,RiskEntryText(),g_chart_fg,g_chart_bg);
   RiskAddTag(g_rgys,RiskStopText(),FPR_LOSS,clrWhite);
   // Targets are numbered from the nearest.
   int order[FPR_MAX_TP];
   int m=0;
   for(int k=0;k<g_rview.ntp;k++)if(g_rgty[k]!=FP_OFF)order[m++]=k;
   for(int i=1;i<m;i++){int v=order[i],j=i;while(j>0 && MathAbs(g_rview.tp_r[order[j-1]])>MathAbs(g_rview.tp_r[v])){order[j]=order[j-1];j--;}order[j]=v;}
   for(int q=0;q<m;q++)RiskAddTag(g_rgty[order[q]],RiskTargetText(q+1,order[q]),FPR_PROFIT,clrBlack);
   RiskDrawTags(r-U(2));
  }
// While armed: a crosshair with the size for a stop at the pointer.
void RiskCrosshair()
  {
   if(!g_risk.armed || g_risk.active || !g_mouse_in || HitUI(g_mouse_x,g_mouse_y))return;
   int x=g_mouse_x,y=g_mouse_y;
   HLine(0,g_width-1,y,g_chart_fg,1,STYLE_DOT,170);
   VLine(x,0,g_height-1,g_chart_fg,1,STYLE_DOT,170);
   string a="",b="";
   if(!g_risk.market){a="Entry "+DoubleToString(g_risk.stop,_Digits);b="press here and drag to your stop";}
   else
     {
      a="Stop "+DoubleToString(g_rview.stop,_Digits);
      if(g_rview.side==0)b=g_rview.why;
      else
        {
         a+="  "+RiskMoveText(-g_rview.dist);
         if(g_rview.flag==0 || g_rview.flag==2)b=(g_rview.side>0?"BUY ":"SELL ")+RiskLotText(g_rview.lots)+" lots  -"+FPMoney(g_rview.actual)+" "+g_rsym.account_ccy;
         else b="no size: "+g_rview.why;
        }
     }
   int th=g_line_canvas.TextHeight("Ag")+U(4);
   int w=(int)MathMax(g_line_canvas.TextWidth(a),g_line_canvas.TextWidth(b))+U(10);
   int bx=x+U(14),by=y+U(16);
   if(bx+w>=g_width)bx=x-U(14)-w;
   if(by+2*th>=g_height)by=y-U(16)-2*th;
   bx=Lim(bx,0,(int)MathMax(0,g_width-w-1));by=Lim(by,0,(int)MathMax(0,g_height-2*th-1));
   g_line_canvas.FillRectangle(bx,by,bx+w,by+2*th,ColorToARGB(g_chart_bg,230));
   g_line_canvas.Rectangle(bx,by,bx+w,by+2*th,ColorToARGB(g_chart_fg,120));
   g_line_canvas.TextOut(bx+U(5),by+U(2),a,ColorToARGB(g_chart_fg));
   g_line_canvas.TextOut(bx+U(5),by+U(2)+th,b,ColorToARGB(g_chart_fg));
  }

// ---- toolbar button, risk bar (under the toolbar) and the Risk window
bool RiskBarShown(){return g_owner && !g_hidden && (g_risk.armed || g_risk.active);}
int RiskBarY(){return g_toolbar_y+U(FP_TOOLBAR_HEIGHT+2);}
void UpdateRiskButton()
  {
   if(g_hidden || !g_owner)return;
   bool on=g_risk.armed || g_risk.active || g_reditor;
   Button("T.Risk","Risk",g_toolbar_x+U(FP_TOOLBAR_WIDTH-156),g_toolbar_y+U(1),60,18,on?clrLightSteelBlue:clrWhite);
   Tooltip("T.Risk","Lot size from your risk per trade: press on the chart and drag to your stop ("+InpRiskHotkey+")");
  }
bool HitRiskButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-156) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-96) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
string RiskModeText(FPRiskConfig &c)
  {
   if(c.mode==0)return "Risk "+FPMoney(c.amount)+" "+AccountInfoString(ACCOUNT_CURRENCY);
   string pct=FPRNum(c.percent)+"%";
   if(c.mode==1)return "Risk "+pct+" of balance";
   if(c.mode==2)return "Risk "+pct+" of equity";
   return "Risk "+pct+" of "+FPMoney(c.base);
  }
void BuildRiskBar()
  {
   int x=g_toolbar_x+U(8),y=RiskBarY();
   Button("K.Market","Market",x,y,54,22,g_risk.market?clrLightSteelBlue:clrWhite);x+=U(56);
   Button("K.Limit","Limit",x,y,46,22,g_risk.market?clrWhite:clrLightSteelBlue);x+=U(52);
   Button("K.Risk",RiskModeText(g_rcfg),x,y,150);x+=U(156);
   Button("K.Add","+TP",x,y,38);x+=U(40);
   Edit("K.R",g_rcfg.add_r,x,y,44);x+=U(46);
   Label("K.RL","R",x,y+U(4),g_chart_fg);x+=U(14);
   Button("K.Del","-TP",x,y,38);x+=U(44);
   Button("K.Close",Glyph(0xD7),x,y,22);
   Tooltip("K.Market","Entry at the live price: the ask for a buy, the bid for a sell (moves with every tick)");
   Tooltip("K.Limit","Entry at a price you choose: press at the entry and drag to the stop (limit or stop order)");
   Tooltip("K.Risk","Risk per trade, commission and the value of a lot: open the Risk window");
   Tooltip("K.Add","Add targets at the R multiples typed on the right (e.g. 3, or 1.5 3 5)");
   Tooltip("K.R","R multiples for +TP, separated by spaces");
   Tooltip("K.Del","Remove the farthest target (double-click a target line to remove that one)");
   Tooltip("K.Close","Remove the measurement (Esc)");
  }
// The +TP list typed on the bar; false (and the old list back) when it is not a list of R multiples.
bool RiskSetAddR(const string text)
  {
   double r[];
   int n=FPParseRList(text,r,FPR_MAX_TP);
   if(n<=0){Status("Type R multiples such as 3, or 1.5 3 5.");g_ui_dirty=true;return false;}
   string norm=FPRListText(r,n);
   if(norm!=g_rcfg.add_r){g_rcfg.add_r=norm;if(g_reditor)g_redit.add_r=norm;SaveRisk();g_ui_dirty=true;}
   return true;
  }
void RiskBarClick(const string key)
  {
   // Read the typed R list first: the click can arrive before its end-edit event.
   bool listed=true;
   if(key!="Close" && RegFind(UIS("K.R"))>=0)listed=RiskSetAddR(ObjectGetString(0,UIS("K.R"),OBJPROP_TEXT));
   if(key=="Market"){RiskSetMarket(true);return;}
   if(key=="Limit"){RiskSetMarket(false);return;}
   if(key=="Risk"){if(g_reditor)CloseRisk();else OpenRisk();return;}
   if(key=="Add"){if(listed)RiskAddTargets();return;}
   if(key=="Del"){RiskRemoveFarthest();return;}
   if(key=="Close"){RiskClear();return;}
  }
int RiskPanelHeight(){return U(FPR_PANEL_HEIGHT);}
void OpenRisk()
  {
   if(g_editor){Status("Finish or cancel Properties first.");return;}
   if(g_zeditor){Status("Close the Zones window first.");return;}
   if(g_peditor){Status("Close the Price points window first.");return;}
   ClosePopup();g_list=false;g_redit=g_rcfg;g_reditor=true;
   g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
   g_ui_dirty=true;g_dirty=true;
  }
void CloseRisk(){ClosePopup();g_reditor=false;g_ui_dirty=true;g_dirty=true;}
void REndEdit(const string name)
  {
   if(name==UIS("K.R")){if(!RiskSetAddR(ObjectGetString(0,name,OBJPROP_TEXT)))g_edit_error=true;return;}
   if(!g_reditor || StringFind(name,UIS("W."))!=0 || RegType(name)!=OBJ_EDIT)return;
   string key=StringSubstr(name,StringLen(UIS("W."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   StringTrimLeft(text);StringTrimRight(text);
   double v=StringToDouble(text);
   bool number=Numeric(text) && v>=0,accepted=true;
   if(key=="Amount"){if(number)g_redit.amount=v;else accepted=false;}
   else if(key=="Percent"){if(number && v<=100)g_redit.percent=v;else accepted=false;}
   else if(key=="Base"){if(number)g_redit.base=v;else accepted=false;}
   else if(key=="Comm")
     {
      if(StringLen(text)==0){v=0;number=true;}
      if(!number || !FPRSymSet(g_redit,_Symbol,v,FPRManual(g_redit,_Symbol)))accepted=false;
     }
   else if(key=="Targets" || key=="AddR")
     {
      double r[];
      int n=FPParseRList(text,r,FPR_MAX_TP);
      if(n<=0)accepted=false;
      else if(key=="Targets")g_redit.targets=FPRListText(r,n);
      else g_redit.add_r=FPRListText(r,n);
     }
   else if(key=="Value")
     {
      // Typed in the unit shown (per pip on forex), kept per 1.0 price move.
      if(StringLen(text)==0)FPRSymSet(g_redit,_Symbol,FPRCommission(g_redit,_Symbol),0);
      else if(!number || !(v>0) || !FPRSymSet(g_redit,_Symbol,FPRCommission(g_redit,_Symbol),v/RiskUnit()))accepted=false;
     }
   else return;
   if(!accepted){g_edit_error=true;Status("Invalid value; previous setting restored.");g_ui_dirty=true;}
   g_dirty=true;   // the measurement previews the window's settings
  }
bool HarvestRiskEdits()
  {
   if(!g_reditor)return true;
   g_edit_error=false;
   string prefix=UIS("W.");
   for(int i=0;i<g_reg_count;i++)
      if(g_reg[i].type==OBJ_EDIT && StringFind(g_reg[i].name,prefix)==0)REndEdit(g_reg[i].name);
   return !g_edit_error;
  }
bool ApplyRisk(const bool close)
  {
   if(!g_reditor)return false;
   if(!HarvestRiskEdits())return false;
   FPRiskConfig previous=g_rcfg;g_rcfg=g_redit;
   if(!SaveRisk()){g_rcfg=previous;Status("Could not save the risk settings. Check the Experts log.");return false;}
   RiskModeSwitch(g_rcfg.entry==0);
   Status("Risk settings saved for this account.");
   g_dirty=true;
   if(close)CloseRisk();else {ClosePopup();g_ui_dirty=true;}
   return true;
  }
void BuildRiskPanel()
  {
   int x=g_panel_x,y=g_panel_y,W=FP_PANEL_WIDTH;
   string ccy=g_rsym.account_ccy;
   Box("W.Background",x,y,W,FPR_PANEL_HEIGHT,clrWhiteSmoke);
   Label("W.Title","Lot size & risk",x+U(10),y+U(7));
   Label("W.Account","Saved for account "+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+" ("+ccy+")",x+U(250),y+U(7),clrDimGray);
   int cy=y+U(32);
   Label("W.ModeL","Risk per trade",x+U(12),cy+U(4));
   string modes[]={"Fixed amount","% of balance","% of equity","% of fixed base"};
   int mw[]={92,88,82,104};
   int mx=x+U(108);
   for(int m=0;m<4;m++){Button("W.Mode"+IntegerToString(m),modes[m],mx,cy,mw[m],22,g_redit.mode==m?clrLightSteelBlue:clrWhite);mx+=U(mw[m]+2);}
   Tooltip("W.Mode3","A percentage of a fixed amount, e.g. a prop-firm account's starting balance");
   cy+=U(30);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double risk=FPRiskAmount(g_redit.mode,g_redit.amount,g_redit.percent,g_redit.base,balance,equity);
   if(g_redit.mode==0)
     {
      Label("W.AmountL","Amount",x+U(12),cy+U(4));Edit("W.Amount",RiskNumText(g_redit.amount),x+U(108),cy,90);
      Label("W.AmountC",ccy+" per trade",x+U(204),cy+U(4),clrDimGray);
     }
   else
     {
      Label("W.PercentL","Percent",x+U(12),cy+U(4));Edit("W.Percent",RiskNumText(g_redit.percent),x+U(108),cy,56);
      if(g_redit.mode==3)
        {
         Label("W.OfL","% of",x+U(170),cy+U(4));Edit("W.Base",RiskNumText(g_redit.base),x+U(202),cy,90);
         Label("W.OfC",ccy+" = "+FPMoney(risk)+" "+ccy,x+U(298),cy+U(4),clrDimGray);
        }
      else Label("W.OfL",(g_redit.mode==1?"% of balance ":"% of equity ")+FPMoney(g_redit.mode==1?balance:equity)+" = "+FPMoney(risk)+" "+ccy,x+U(170),cy+U(4),clrDimGray);
     }
   cy+=U(28);
   Label("W.CommL","Commission per lot",x+U(12),cy+U(4));
   Edit("W.Comm",RiskNumText(FPRCommission(g_redit,_Symbol)),x+U(130),cy,64);
   Label("W.CommC",ccy+" round turn (open + close), "+_Symbol,x+U(200),cy+U(4),clrDimGray);
   Tooltip("W.Comm","Per 1.00 lot for opening and closing together; added to the loss at the stop. Saved per symbol.");
   cy+=U(28);
   Label("W.EntryL","Entry",x+U(12),cy+U(4));
   Button("W.Entry0","Market price",x+U(108),cy,110,22,g_redit.entry==0?clrLightSteelBlue:clrWhite);
   Button("W.Entry1","A price I choose (limit / stop)",x+U(220),cy,196,22,g_redit.entry==1?clrLightSteelBlue:clrWhite);
   cy+=U(28);
   Label("W.TargetsL","Targets (R)",x+U(12),cy+U(4));
   Edit("W.Targets",g_redit.targets,x+U(108),cy,90);
   Label("W.AddRL","+TP adds",x+U(208),cy+U(4));
   Edit("W.AddR",g_redit.add_r,x+U(266),cy,70);
   Label("W.TargetsC","R, e.g. 2 or 1 2 3",x+U(342),cy+U(4),clrDimGray);
   Tooltip("W.Targets","Targets every new measurement starts with, in R (1R = the distance to the stop)");
   cy+=U(32);
   Box("W.Rule",x+U(10),cy,W-20,1,clrSilver);
   cy+=U(8);
   // The value of 1.00 lot on this symbol, by method, in the unit shown.
   double unit=RiskUnit(),value=0;bool disagree=false;
   string ut=RiskUnitText();
   int source=FPValueDecide(FPRManual(g_redit,_Symbol),g_rval.calib,g_rval.contract,g_rval.tick,value,disagree);
   Label("W.ValueT","Value of 1.00 lot of "+_Symbol,x+U(12),cy);
   cy+=U(20);
   string used=value>0?FPMoney(value*unit)+" "+ccy+" "+ut+"  ("+RiskSourceText(source)+")":(disagree?"none: the two methods below disagree":"none: no method below gives a value");
   Label("W.Used","Used: "+used,x+U(12),cy,value>0?clrBlack:clrFireBrick);
   cy+=U(20);
   Label("W.Contract","Contract size "+RiskNumText(g_rsym.contract)+": "+(g_rval.contract>0?FPMoney(g_rval.contract*unit)+" "+ccy+" "+ut:"not available"),x+U(12),cy,clrDimGray);
   cy+=U(18);
   Label("W.Tick","Tick value: "+(g_rval.tick>0?FPMoney(g_rval.tick*unit)+" "+ccy+" "+ut:"not available")+(disagree?"  - does not match":""),x+U(12),cy,disagree?clrFireBrick:clrDimGray);
   cy+=U(18);
   string cal=!g_rcal_found?"none - run the script Fibonacci_Pro_Calibrate":(g_rval.calib_stale?"out of date (contract size changed): run the script again"
              :(g_rval.calib>0?FPMoney(g_rval.calib*unit)+" "+ccy+" "+ut+", "+TimeToString((datetime)g_rcal.time,TIME_DATE|TIME_MINUTES):"no rate to convert "+g_rcal.profit_ccy+" to "+ccy));
   Label("W.Calib","Calibration: "+cal,x+U(12),cy,clrDimGray);
   Tooltip("W.Calib","The script measures each Market Watch symbol with the terminal's own profit calculation. It sends no orders.");
   Button("W.Reload","Reload",x+U(W-72),cy-U(3),60,20);
   cy+=U(24);
   Label("W.ValueL","Your own value",x+U(12),cy+U(4));
   double manual=FPRManual(g_redit,_Symbol);
   Edit("W.Value",manual>0?RiskNumText(manual*unit):"",x+U(108),cy,80);
   Label("W.ValueC",ccy+" "+ut+" (empty: automatic)",x+U(194),cy+U(4),clrDimGray);
   Tooltip("W.Value","From your broker's contract specification. It takes priority over every other method.");
   cy+=U(26);
   Button("W.UseContract","Use contract size",x+U(108),cy,120,22);
   Button("W.UseTick","Use tick value",x+U(230),cy,104,22);
   Button("W.ClearValue","Clear",x+U(336),cy,56,22);
   cy+=U(28);
   Label("W.Volume","Volume: min "+RiskLotText(g_rsym.vmin)+", step "+RiskLotText(g_rsym.vstep)+", max "+RiskLotText(g_rsym.vmax)+" (lots round down)",x+U(12),cy,clrDimGray);
   int by=y+U(FPR_PANEL_HEIGHT-31);
   Button("W.OK","OK",x+U(W-246),by,72);Button("W.Cancel","Cancel",x+U(W-172),by,72);Button("W.Apply","Apply",x+U(W-98),by,72);
  }
void RiskPanelClick(const string key)
  {
   if(key!="Cancel")
     {
      // Read active edits before their focus-loss events or an Apply click race.
      if(!HarvestRiskEdits())return;
      if(g_ui_dirty){ClosePopup();BuildUI();}
     }
   if(key=="OK"){ApplyRisk(true);return;}
   if(key=="Apply"){ApplyRisk(false);return;}
   if(key=="Cancel"){CloseRisk();return;}
   if(key=="Reload")
     {
      g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
      Status(g_rcal_found?"Calibration of "+_Symbol+" loaded.":"No calibration for "+_Symbol+" yet: run the script Fibonacci_Pro_Calibrate.");
     }
   else if(StringFind(key,"Mode")==0)g_redit.mode=Lim((int)StringToInteger(StringSubstr(key,4)),0,3);
   else if(StringFind(key,"Entry")==0)g_redit.entry=Lim((int)StringToInteger(StringSubstr(key,5)),0,1);
   else if(key=="UseContract" || key=="UseTick")
     {
      double v=key=="UseContract"?g_rval.contract:g_rval.tick;
      if(!(v>0)){Status("That method gives no value for "+_Symbol+".");return;}
      if(!FPRSymSet(g_redit,_Symbol,FPRCommission(g_redit,_Symbol),v)){Status("Too many symbols with settings of their own.");return;}
     }
   else if(key=="ClearValue")FPRSymSet(g_redit,_Symbol,FPRCommission(g_redit,_Symbol),0);
   else return;   // Unknown command: keep the window (and any edit focus) as it is.
   g_ui_dirty=true;g_dirty=true;
  }
// Every frame: a market entry follows the quotes; the account and the symbol value are re-read.
void RiskTick(const ulong now)
  {
   if(!g_owner || (!g_risk.armed && !g_risk.active && !g_reditor))return;
   if(now-g_rinfo_tick>=2000)
     {
      g_rinfo_tick=now;
      double c=g_rval.contract,t=g_rval.tick,k=g_rval.calib;
      RiskPollShared();RiskRefreshValue();
      if(c!=g_rval.contract || t!=g_rval.tick || k!=g_rval.calib)g_dirty=true;
     }
   if(!g_risk.armed && !g_risk.active)return;
   bool quotes=SymbolInfoDouble(_Symbol,SYMBOL_BID)!=g_rlast_bid || SymbolInfoDouble(_Symbol,SYMBOL_ASK)!=g_rlast_ask;
   if(quotes && g_risk.market)g_dirty=true;
   else if(now-g_rtick>=500)
     {
      g_rtick=now;
      if(quotes || AccountInfoDouble(ACCOUNT_BALANCE)!=g_rlast_bal || AccountInfoDouble(ACCOUNT_EQUITY)!=g_rlast_eq)g_dirty=true;
     }
  }

// ------------------------------------------------------------ price points (1.67-1.69)
// ---- rows: names, parts, the default list, sorting
string FPPGroupName(const int g)
  {string n[]={"Gaps","Pre-sessions","Opening ranges","FPFVG & FPOB","Sessions","OHLC"};return n[Lim(g,0,FPP_GROUPS-1)];}
// Parts a row of this kind can draw. Every kind with a range (all but an open) can add its
// quadrants and octants.
int FPPAllowed(const int kind)
  {
   if(kind==FPPK_OPEN)return FPPP_O;
   int split=FPPP_CE|FPPP_Q|FPPP_E;
   if(kind==FPPK_WINDOW || kind==FPPK_FVG || kind==FPPK_OB)return FPPP_H|FPPP_L|FPPP_BOX|split;
   if(kind==FPPK_GAP)return FPPP_O|FPPP_C|FPPP_BOX|split;
   return FPPP_O|FPPP_H|FPPP_L|FPPP_C|split;
  }
// The parts bit that shows line `part` (one bit for both quadrants, one for the four octants).
int FPPBitOf(const int part){if(part<6)return 1<<part;return part<8?FPPP_Q:FPPP_E;}
// Where a quadrant or octant line sits in its range, from the low.
double FPPFrac(const int part)
  {
   if(part==6)return 0.25;
   if(part==7)return 0.75;
   return 0.125+0.25*(part-8);
  }
string FPPPct(const int part)
  {string n[]={"25%","75%","12.5%","37.5%","62.5%","87.5%"};return n[Lim(part-6,0,5)];}
// Lines that price can take, by index (a window's range box is a fixed rectangle, a zone's
// box is filled when its far edge is taken).
int FPPTakeable(const int kind)
  {
   int allowed=FPPAllowed(kind),m=0;
   for(int q=0;q<FPP_PARTS;q++)if(q!=3 && (allowed&FPPBitOf(q))!=0)m|=1<<q;
   return m;
  }
// 0 one per trading day, 1 one per week, 2 one per month.
int FPPCadence(FPPoint &p)
  {
   if((p.kind==FPPK_GAP && p.sub==2) || (p.kind==FPPK_PERIOD && p.sub==1))return 1;
   if(p.kind==FPPK_PERIOD && p.sub==2)return 2;
   return p.sample==1?1:0;
  }
string FPPKindText(FPPoint &p)
  {
   if(p.kind==FPPK_WINDOW)return "High and low of a time window";
   if(p.kind==FPPK_OPEN)return "Opening price at a time";
   if(p.kind==FPPK_FVG)return "First M1 fair value gap of a window";
   if(p.kind==FPPK_OB)return "First M1 order block before a break of structure";
   if(p.kind==FPPK_GAP)
     {
      if(p.sub==0)return "Opening range gap: the prior session's close to the open";
      if(p.sub==1)return "New day opening gap: the close before 17:00 to the reopen";
      return "New week opening gap: Friday's close to the week's open";
     }
   if(p.sub==0)return "Trading day, 17:00 to 17:00 New York";
   return p.sub==1?"Week":"Month";
  }
// A row's name on the chart: its short name (AS, LN, NY for the sessions), else its name.
string FPPShort(FPPoint &p){return StringLen(p.sname)>0?p.sname:p.name;}
// Name of one line of a row (as drawn and shown in hover).
string FPPPartName(FPPoint &p,const int part)
  {
   string nm=FPPShort(p);
   if(part==3)return nm;
   if(part==2)return nm+" CE";
   if(part>=6)return nm+" "+FPPPct(part);
   if(p.kind==FPPK_PERIOD)
     {
      string per=p.sub==0?"D":(p.sub==1?"W":"M");
      if(part==0)return "HO"+per;
      if(part==1)return "LO"+per;
      if(part==4)return "OO"+per;
      return "CO"+per;
     }
   if(p.kind==FPPK_FVG || p.kind==FPPK_OB)return part==0?nm+" top":nm+" bottom";
   string own=(part==0 || part==4)?p.hname:p.lname;
   if(StringLen(own)>0)return own;
   if(part==4)return p.kind==FPPK_OPEN?nm:nm+" open";
   if(part==5)return nm+" close";
   return part==0?nm+" high":nm+" low";
  }
void FPPSet(FPPoint &p,const string name,const string hn,const string ln,const int kind,const int sub,const int group,const int start,const int end,const int parts,const color ink,const bool on)
  {
   p.enabled=on;p.name=name;p.hname=hn;p.lname=ln;p.sname="";p.kind=kind;p.sub=sub;p.group=group;p.start=start;p.end=end;
   p.len=30;p.swing=1;p.look=10;p.parts=parts&FPPAllowed(kind);p.style=-1;p.width=1;p.ink=ink;
   p.label=0;p.ends=0;p.sample=0;p.bold=0;p.ray=false;p.alert=false;p.uid=0;
  }
// The 30 rows: every level of the ICT price point list (55 lines), in six groups.
// Switched on at first: the Asia, London and New York session highs and lows, and NDOG.
void FPPDefaultList(FPPointConfig &c)
  {
   int n=0,hl=FPPP_H|FPPP_L,gap=FPPP_O|FPPP_C|FPPP_CE|FPPP_BOX,zone=FPPP_BOX|FPPP_CE;
   FPPSet(c.rows[n++],"ORG","RTH open","RTH close",FPPK_GAP,0,0,974,570,gap,clrDarkTurquoise,false);
   FPPSet(c.rows[n++],"NDOG","NDOG open","NDOG close",FPPK_GAP,1,0,1019,1020,gap,clrHotPink,true);
   FPPSet(c.rows[n++],"NWOG","NWOG open","NWOG close",FPPK_GAP,2,0,1019,1020,gap,clrOrchid,false);
   FPPSet(c.rows[n++],"MN PreS","MN PreSH","MN PreSL",FPPK_WINDOW,0,1,1260,0,hl,clrCrimson,false);
   FPPSet(c.rows[n++],"LN PreS","LN PreSH","LN PreSL",FPPK_WINDOW,0,1,60,180,hl,clrRoyalBlue,false);
   FPPSet(c.rows[n++],"NY PreS","NY PreSH","NY PreSL",FPPK_WINDOW,0,1,480,570,hl,clrMediumSeaGreen,false);
   FPPSet(c.rows[n++],"London Close","LCH","LCL",FPPK_WINDOW,0,1,600,720,hl,clrOrange,false);
   FPPSet(c.rows[n++],"NY Lunch","Lunch H","Lunch L",FPPK_WINDOW,0,1,720,810,hl,clrGray,false);
   FPPSet(c.rows[n++],"Midnight open","MNO","",FPPK_OPEN,0,2,0,0,FPPP_O,clrCrimson,false);
   FPPSet(c.rows[n++],"MN OR","MN ORH","MN ORL",FPPK_WINDOW,0,2,0,30,hl,clrCrimson,false);
   FPPSet(c.rows[n++],"LN OR","LN ORH","LN ORL",FPPK_WINDOW,0,2,180,210,hl,clrRoyalBlue,false);
   FPPSet(c.rows[n++],"NY AM OR","NY ORH","NY ORL",FPPK_WINDOW,0,2,570,600,hl,clrMediumSeaGreen,false);
   FPPSet(c.rows[n++],"LC OR","LC ORH","LC ORL",FPPK_WINDOW,0,2,600,630,hl,clrOrange,false);
   FPPSet(c.rows[n++],"NY PM OR","PM ORH","PM ORL",FPPK_WINDOW,0,2,810,840,hl,clrGoldenrod,false);
   string pre[]={"MN","LN","NY","LC","NY"};
   string post[]={"","","AM","","PM"};
   int at[]={0,180,570,600,810};
   color ink[]={clrCrimson,clrRoyalBlue,clrMediumSeaGreen,clrOrange,clrGoldenrod};
   for(int k=0;k<5;k++)
     {
      string tail=StringLen(post[k])>0?" "+post[k]:"";
      FPPSet(c.rows[n++],pre[k]+" FPFVG"+tail,"","",FPPK_FVG,0,3,at[k],at[k]+30,zone,ink[k],false);
      FPPSet(c.rows[n++],pre[k]+" FPOB"+tail,"","",FPPK_OB,0,3,at[k],at[k]+30,zone,ink[k],false);
     }
   FPPSet(c.rows[n++],"Asia","ASH","ASL",FPPK_WINDOW,0,4,1140,240,hl,clrMediumPurple,true);c.rows[n-1].sname="AS";
   FPPSet(c.rows[n++],"London","LNH","LNL",FPPK_WINDOW,0,4,180,720,hl,clrRoyalBlue,true);c.rows[n-1].sname="LN";
   FPPSet(c.rows[n++],"New York","NYH","NYL",FPPK_WINDOW,0,4,480,1020,hl,clrMediumSeaGreen,true);c.rows[n-1].sname="NY";
   FPPSet(c.rows[n++],"Day","","",FPPK_PERIOD,0,5,0,0,hl,clrSilver,false);
   FPPSet(c.rows[n++],"Week","","",FPPK_PERIOD,1,5,0,0,hl,clrLightSteelBlue,false);
   FPPSet(c.rows[n++],"Month","","",FPPK_PERIOD,2,5,0,0,hl,clrCadetBlue,false);
   c.count=n;
   for(int i=0;i<n;i++)c.rows[i].uid=(uint)(i+1);
  }
// Every field set, rows beyond the count too, so a whole-config copy carries no stale data.
void FPPClear(FPPointConfig &c)
  {
   c.enabled=false;c.end_taken=false;c.merge=false;c.pin_left=false;c.offscreen=false;c.hover=false;c.fill=false;c.range_fill=false;
   c.alert_sound=false;c.alert_push=false;
   for(int g=0;g<FPP_GROUPS;g++){c.group_on[g]=false;c.group_tf[g]=0;}
   c.days_back=1;c.weeks_back=1;c.months_back=1;c.taken_end=0;c.taken_show=0;c.week_open=0;c.label_mode=0;c.label_size=10;c.label_bold=false;
   c.opacity=0;c.tint=0;c.count=0;
   for(int i=0;i<FPP_MAX;i++)FPPSet(c.rows[i],"","","",FPPK_WINDOW,0,0,0,0,0,clrNONE,false);
  }
void FPPDefaults(FPPointConfig &c)
  {
   FPPClear(c);
   c.enabled=true;
   for(int g=0;g<FPP_GROUPS;g++)c.group_on[g]=true;
   c.group_tf[0]=14;c.group_tf[1]=11;c.group_tf[2]=8;c.group_tf[3]=4;c.group_tf[4]=14;c.group_tf[5]=19; // H4 H1 M15 M5 H4 W1
   c.days_back=10;c.weeks_back=4;c.months_back=3;
   c.end_taken=true;c.taken_end=0;c.taken_show=0;c.week_open=0;
   c.label_mode=0;c.label_size=10;c.label_bold=false;c.merge=true;c.pin_left=false;c.offscreen=true;c.hover=true;
   c.fill=true;c.opacity=14;c.tint=0;c.range_fill=false;
   c.alert_sound=true;c.alert_push=true;
   FPPDefaultList(c);
  }
// A new row's identity: never one in use, nor one this chart still keeps hidden or rayed levels for.
uint FPPNewUid(FPPointConfig &c)
  {
   uint m=0;
   for(int i=0;i<c.count;i++)if(c.rows[i].uid>m)m=c.rows[i].uid;
   for(int i=0;i<g_pflag_n;i++)if(g_pflags[i].uid>m)m=g_pflags[i].uid;
   return m+1;
  }
// Trading-day order (evening rows first); gaps by their open, periods last.
int FPPSortKey(FPPoint &p)
  {
   if(p.kind==FPPK_PERIOD)return 2000+p.sub;
   int t=p.kind==FPPK_GAP?(p.sub==2?-1500:p.end):p.start;
   return t>=1020?t-1440:t;
  }
// mode 1 by name, 2 by time; stable, so equal keys keep their order.
void FPPSort(FPPointConfig &c,const int mode,const bool desc)
  {
   for(int i=1;i<c.count;i++)
     {
      FPPoint v=c.rows[i];int j=i;
      while(j>0)
        {
         int cmp=mode==1?StringCompare(c.rows[j-1].name,v.name,false):FPPSortKey(c.rows[j-1])-FPPSortKey(v);
         if(desc?cmp>=0:cmp<=0)break;
         c.rows[j]=c.rows[j-1];j--;
        }
      c.rows[j]=v;
     }
  }

// ---- settings files (shared by every chart of the workspace) and presets
// Schema 2 (1.68) adds where taken lines end, bold labels (global and per row), the end
// of day and end of week choices per row, quadrants and octants, and 120 days back.
// Schema 3 (1.69) adds each row's name on the chart. Version 1.67 reads only schema 1, 1.68
// schemas 1 and 2, 1.69 all three; the session rows of older files take the short names.
void FPPWriteConfig(const int f,FPPointConfig &c)
  {
   FileWriteInteger(f,FPP_MAGIC);FileWriteInteger(f,FPP_SCHEMA);
   int flags=(c.enabled?1:0)|(c.end_taken?2:0)|(c.merge?4:0)|(c.pin_left?8:0)|(c.offscreen?16:0)|(c.hover?32:0)
             |(c.fill?64:0)|(c.range_fill?128:0)|(c.alert_sound?256:0)|(c.alert_push?512:0)|(c.label_bold?1024:0);
   FileWriteInteger(f,flags);
   for(int g=0;g<FPP_GROUPS;g++)FileWriteInteger(f,(c.group_on[g]?1:0)|(c.group_tf[g]<<1));
   FileWriteInteger(f,c.days_back);FileWriteInteger(f,c.weeks_back);FileWriteInteger(f,c.months_back);
   FileWriteInteger(f,c.taken_show);FileWriteInteger(f,c.week_open);FileWriteInteger(f,c.label_mode);FileWriteInteger(f,c.label_size);
   FileWriteInteger(f,c.opacity);FileWriteInteger(f,c.tint);FileWriteInteger(f,c.taken_end);
   FileWriteInteger(f,c.count);
   for(int i=0;i<c.count;i++)
     {
      WText(f,c.rows[i].name);WText(f,c.rows[i].hname);WText(f,c.rows[i].lname);WText(f,c.rows[i].sname);
      FileWriteInteger(f,c.rows[i].kind);FileWriteInteger(f,c.rows[i].sub);FileWriteInteger(f,c.rows[i].group);
      FileWriteInteger(f,c.rows[i].start);FileWriteInteger(f,c.rows[i].end);FileWriteInteger(f,c.rows[i].len);
      FileWriteInteger(f,c.rows[i].swing);FileWriteInteger(f,c.rows[i].look);FileWriteInteger(f,c.rows[i].parts);
      FileWriteInteger(f,c.rows[i].style);FileWriteInteger(f,c.rows[i].width);FileWriteInteger(f,(int)c.rows[i].ink);
      FileWriteInteger(f,c.rows[i].label);FileWriteInteger(f,c.rows[i].ends);FileWriteInteger(f,c.rows[i].sample);
      FileWriteInteger(f,c.rows[i].bold);
      FileWriteInteger(f,(int)c.rows[i].uid);
      FileWriteInteger(f,(c.rows[i].enabled?1:0)|(c.rows[i].ray?2:0)|(c.rows[i].alert?4:0));
     }
   FileWriteInteger(f,FPP_END);
  }
// A session row of an older file, still named as the defaults were, takes the short names
// (AS, LN, NY; London's lines LNH and LNL). Names the user changed are left alone.
void FPPShortSessions(FPPoint &p)
  {
   if(p.kind!=FPPK_WINDOW || StringLen(p.sname)>0)return;
   if(p.name=="Asia")p.sname="AS";
   else if(p.name=="New York")p.sname="NY";
   else if(p.name=="London")
     {
      p.sname="LN";
      if(p.hname=="LSH")p.hname="LNH";
      if(p.lname=="LSL")p.lname="LNL";
     }
  }
bool FPPReadConfig(const int f,FPPointConfig &c)
  {
   if(FileReadInteger(f)!=FPP_MAGIC)return false;
   int schema=FileReadInteger(f);
   if(schema<1 || schema>FPP_SCHEMA)return false;
   int flags=FileReadInteger(f);
   c.enabled=(flags&1)!=0;c.end_taken=(flags&2)!=0;c.merge=(flags&4)!=0;c.pin_left=(flags&8)!=0;c.offscreen=(flags&16)!=0;
   c.hover=(flags&32)!=0;c.fill=(flags&64)!=0;c.range_fill=(flags&128)!=0;c.alert_sound=(flags&256)!=0;c.alert_push=(flags&512)!=0;
   c.label_bold=schema>=2 && (flags&1024)!=0;
   for(int g=0;g<FPP_GROUPS;g++)
     {int v=FileReadInteger(f);c.group_on[g]=(v&1)!=0;c.group_tf[g]=v>>1;if(c.group_tf[g]<0 || c.group_tf[g]>20)return false;}
   c.days_back=FileReadInteger(f);c.weeks_back=FileReadInteger(f);c.months_back=FileReadInteger(f);
   c.taken_show=FileReadInteger(f);c.week_open=FileReadInteger(f);c.label_mode=FileReadInteger(f);c.label_size=FileReadInteger(f);
   c.opacity=FileReadInteger(f);c.tint=FileReadInteger(f);
   c.taken_end=schema>=2?FileReadInteger(f):0;
   c.count=FileReadInteger(f);
   if(c.days_back<1 || c.days_back>120 || c.weeks_back<1 || c.weeks_back>26 || c.months_back<1 || c.months_back>12
      || c.taken_show<0 || c.taken_show>2 || c.week_open<0 || c.week_open>1 || c.label_mode<0 || c.label_mode>3
      || c.label_size<8 || c.label_size>24 || c.opacity<0 || c.opacity>100 || c.tint<0 || c.tint>1 || c.taken_end<0 || c.taken_end>2
      || c.count<0 || c.count>FPP_MAX)return false;
   for(int i=0;i<c.count;i++)
     {
      if(!RText(f,c.rows[i].name,40) || !RText(f,c.rows[i].hname,24) || !RText(f,c.rows[i].lname,24))return false;
      c.rows[i].sname="";
      if(schema>=3 && !RText(f,c.rows[i].sname,16))return false;
      c.rows[i].kind=FileReadInteger(f);c.rows[i].sub=FileReadInteger(f);c.rows[i].group=FileReadInteger(f);
      c.rows[i].start=FileReadInteger(f);c.rows[i].end=FileReadInteger(f);c.rows[i].len=FileReadInteger(f);
      c.rows[i].swing=FileReadInteger(f);c.rows[i].look=FileReadInteger(f);c.rows[i].parts=FileReadInteger(f);
      c.rows[i].style=FileReadInteger(f);c.rows[i].width=FileReadInteger(f);c.rows[i].ink=(color)FileReadInteger(f);
      c.rows[i].label=FileReadInteger(f);c.rows[i].ends=FileReadInteger(f);c.rows[i].sample=FileReadInteger(f);
      c.rows[i].bold=schema>=2?FileReadInteger(f):0;
      c.rows[i].uid=(uint)FileReadInteger(f);
      int rf=FileReadInteger(f);
      c.rows[i].enabled=(rf&1)!=0;c.rows[i].ray=(rf&2)!=0;c.rows[i].alert=(rf&4)!=0;
      int k=c.rows[i].kind;
      if(k<0 || k>5 || c.rows[i].sub<0 || c.rows[i].sub>((k==FPPK_GAP || k==FPPK_PERIOD)?2:0) || c.rows[i].group<0 || c.rows[i].group>=FPP_GROUPS
         || c.rows[i].start<0 || c.rows[i].start>1439 || c.rows[i].end<0 || c.rows[i].end>1439 || c.rows[i].len<1 || c.rows[i].len>240
         || c.rows[i].swing<1 || c.rows[i].swing>5 || c.rows[i].look<0 || c.rows[i].look>60 || (c.rows[i].parts&~FPPAllowed(k))!=0
         || c.rows[i].style<-1 || c.rows[i].style>4 || c.rows[i].width<1 || c.rows[i].width>5 || c.rows[i].label<0 || c.rows[i].label>4
         || c.rows[i].ends<0 || c.rows[i].ends>4 || c.rows[i].sample<0 || c.rows[i].sample>1 || c.rows[i].bold<0 || c.rows[i].bold>2
         || c.rows[i].uid==0)return false;
      for(int j=0;j<i;j++)if(c.rows[j].uid==c.rows[i].uid)return false;
      if(schema<3)FPPShortSessions(c.rows[i]);
     }
   return FileReadInteger(f)==FPP_END;
  }
bool FPPReadFile(const string filename,FPPointConfig &c)
  {
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   FPPointConfig candidate;
   FPPClear(candidate);
   bool good=FPPReadConfig(f,candidate) && FileTell(f)==FileSize(f);
   FileClose(f);
   if(good)c=candidate;
   return good;
  }
// Written to a temporary file, verified by reading it back, then swapped in (old copy kept as .bak).
bool FPPWriteFile(const string filename,FPPointConfig &c)
  {
   string temporary=filename+".tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
   if(f==INVALID_HANDLE)return false;
   ResetLastError();FPPWriteConfig(f,c);FileFlush(f);int error=GetLastError();FileClose(f);
   FPPointConfig check;
   if(error!=0 || !FPPReadFile(temporary,check) || check.count!=c.count)return false;
   if(FileIsExist(filename) && !FileCopy(filename,0,filename+".bak",FILE_REWRITE))return false;
   return FileMove(temporary,0,filename,FILE_REWRITE);
  }
bool SavePoints()
  {
   if(g_pstore=="" || !g_owner)return false;
   if(!FPPWriteFile(g_pstore,g_pcfg)){Print("Fibonacci Pro: could not save price point settings, error ",GetLastError());return false;}
   g_pstore_mtime=(datetime)FileGetInteger(g_pstore,FILE_MODIFY_DATE);
   return true;
  }
void LoadPoints()
  {
   if(!FPPReadFile(g_pstore,g_pcfg) && !FPPReadFile(g_pstore+".bak",g_pcfg))FPPDefaults(g_pcfg);
   g_pstore_mtime=FileIsExist(g_pstore)?(datetime)FileGetInteger(g_pstore,FILE_MODIFY_DATE):0;
   g_pact=g_pcfg;g_pocc_dirty=true;
   PPLoadFlags();
  }
// Another chart of the workspace saved new settings: use them.
void PPPollShared()
  {
   if(g_peditor || g_pstore=="" || !FileIsExist(g_pstore))return;
   datetime m=(datetime)FileGetInteger(g_pstore,FILE_MODIFY_DATE);
   if(m<=0 || m==g_pstore_mtime)return;
   FPPointConfig loaded;
   if(!FPPReadFile(g_pstore,loaded))return;
   g_pcfg=loaded;g_pact=g_pcfg;g_pstore_mtime=m;g_pocc_dirty=true;g_dirty=true;
  }

// ---- price points rayed, hidden or extended on this chart (stored next to its drawings)
int PPFlagFind(const uint uid,const long key,const int part)
  {for(int i=0;i<g_pflag_n;i++)if(g_pflags[i].uid==uid && g_pflags[i].key==key && g_pflags[i].part==part)return i;return -1;}
// Reads the chart's file: the 1.69 layout (per line, with ends), or the one 1.67 and 1.68
// wrote (whole occurrences).
void PPLoadFlags()
  {
   g_pflag_n=0;
   if(g_pflag_store=="")return;
   int f=FileOpen(g_pflag_store,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return;
   int magic=FileReadInteger(f);
   bool v2=magic==FPP_FLAGS2_MAGIC,good=v2 || magic==FPP_FLAGS_MAGIC;
   int n=good?FileReadInteger(f):0;
   if(n<0 || n>FPP_FLAGS_MAX)good=false;
   if(good)
     {
      ArrayResize(g_pflags,n);
      for(int i=0;i<n;i++)
        {
         g_pflags[i].uid=(uint)FileReadInteger(f);g_pflags[i].key=FileReadLong(f);
         g_pflags[i].part=v2?FileReadInteger(f):-1;
         g_pflags[i].flags=FileReadInteger(f)&15;
         g_pflags[i].end=v2?(datetime)FileReadLong(f):0;
         if(g_pflags[i].part<-1 || g_pflags[i].part>=FPP_PARTS)good=false;
        }
      good=good && FileReadInteger(f)==(v2?FPP_FLAGS2_END:FPP_FLAGS_END);
      if(good)g_pflag_n=n;
     }
   FileClose(f);
  }
bool PPSaveFlags()
  {
   if(g_pflag_store=="" || !g_owner)return false;
   int f=FileOpen(g_pflag_store,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE)return false;
   FileWriteInteger(f,FPP_FLAGS2_MAGIC);FileWriteInteger(f,g_pflag_n);
   for(int i=0;i<g_pflag_n;i++)
     {
      FileWriteInteger(f,(int)g_pflags[i].uid);FileWriteLong(f,g_pflags[i].key);FileWriteInteger(f,g_pflags[i].part);
      FileWriteInteger(f,g_pflags[i].flags);FileWriteLong(f,(long)g_pflags[i].end);
     }
   FileWriteInteger(f,FPP_FLAGS2_END);FileClose(f);
   return true;
  }
// What is stored for an occurrence, onto its drawn copy.
void PPApplyFlags(FPPOcc &o)
  {
   o.flags=0;
   for(int q=0;q<FPP_PARTS;q++){o.pflags[q]=0;o.pend[q]=0;}
   for(int i=0;i<g_pflag_n;i++)
     {
      if(g_pflags[i].uid!=o.uid || g_pflags[i].key!=o.key)continue;
      int q=g_pflags[i].part;
      if(q<0)o.flags=g_pflags[i].flags;
      else {o.pflags[q]=g_pflags[i].flags;o.pend[q]=g_pflags[i].end;}
     }
  }
// Stores the flags and end of one line (part) or of a whole occurrence (part -1), and
// updates its drawn copy. No flags and no end remove the entry.
bool PPSetFlags(const uint uid,const long key,const int part,const int flags,const datetime end)
  {
   int i=PPFlagFind(uid,key,part);
   if(flags==0 && end==0){if(i>=0){for(int k=i;k<g_pflag_n-1;k++)g_pflags[k]=g_pflags[k+1];g_pflag_n--;}}
   else if(i>=0){g_pflags[i].flags=flags;g_pflags[i].end=end;}
   else
     {
      if(g_pflag_n>=FPP_FLAGS_MAX){Status("Too many price points rayed, hidden or extended on this chart; reset some first.");return false;}
      if(ArraySize(g_pflags)<=g_pflag_n)ArrayResize(g_pflags,g_pflag_n+32);
      g_pflags[g_pflag_n].uid=uid;g_pflags[g_pflag_n].key=key;g_pflags[g_pflag_n].part=part;
      g_pflags[g_pflag_n].flags=flags;g_pflags[g_pflag_n].end=end;g_pflag_n++;
     }
   for(int o=0;o<g_pocc_n;o++)if(g_pocc[o].uid==uid && g_pocc[o].key==key)PPApplyFlags(g_pocc[o]);
   PPSaveFlags();g_dirty=true;
   return true;
  }
int PPHiddenCount(const uint uid)
  {int n=0;for(int i=0;i<g_pflag_n;i++)if(g_pflags[i].uid==uid && (g_pflags[i].flags&4)!=0)n++;return n;}
void PPShowHidden(const uint uid)
  {
   for(int i=g_pflag_n-1;i>=0;i--)
      if(g_pflags[i].uid==uid && (g_pflags[i].flags&4)!=0)
         PPSetFlags(uid,g_pflags[i].key,g_pflags[i].part,g_pflags[i].flags&~4,g_pflags[i].end);
  }

// ---- occurrence windows: New York time to the broker's clock
long FPPPrevWeekday(long day){day--;while(FPDow(day)==0 || FPDow(day)==6)day--;return day;}
long FPPWeekOf(const long td){return td-(FPDow(td)+6)%7;}   // Monday of the trading week
long FPPMonthOf(const long td){int y=0,m=0,d=0;FPCivilFromDays(td,y,m,d);return (long)y*12+m-1;}
// Server-time window of row p for `key`: a window's start and end; an open's time (ts==te);
// a gap's close candle (ts) and the time from which its open is searched (te); a period's
// start and end. False when the row has no occurrence there (Monday's NDOG is the NWOG).
bool FPPWindow(FPPoint &p,const long key,const int week_open,const int mode,const int gmt,datetime &ts,datetime &te)
  {
   long s=0,e=0;
   if(p.kind==FPPK_WINDOW){s=FPZoneNYStart(key,p.start);e=FPZoneNYEnd(s,p.start,p.end);if(e==s)return false;}
   else if(p.kind==FPPK_OPEN){s=FPZoneNYStart(key,p.start);e=s;}
   else if(p.kind==FPPK_FVG || p.kind==FPPK_OB){s=FPZoneNYStart(key,p.start);e=s+(long)Lim(p.len,1,240)*60;}
   else if(p.kind==FPPK_GAP)
     {
      if(p.sub==2)
        {
         s=FPZoneNYStart(key-3,p.start);                        // Friday's close candle
         if(week_open==1){ts=(datetime)FPNYToServer(s,mode,gmt);te=(datetime)(key*86400);return true;}   // Monday 00:00, server clock
         e=(key-1)*86400;                                       // after the weekend: searched from Sunday 00:00 New York
        }
      else
        {
         if(p.sub==1 && FPDow(key)==1)return false;
         s=FPZoneNYStart(FPPPrevWeekday(key),p.start);
         e=FPZoneNYStart(key,p.end);
         if(e<=s)return false;
        }
     }
   else if(p.sub==0){s=(key-1)*86400+1020*60;e=key*86400+1020*60;}
   else if(p.sub==1)
     {
      e=(key+4)*86400+1020*60;                                  // Friday 17:00 New York
      if(week_open==1){ts=(datetime)(key*86400);te=(datetime)FPNYToServer(e,mode,gmt);return true;}
      s=(key-1)*86400;
     }
   else
     {
      int y=(int)(key/12),m=(int)(key%12)+1;
      long d0=FPDaysFromCivil(y,m,1),d1=d0+FPDaysInMonth(y,m)-1;
      s=(d0-1)*86400+1020*60;e=d1*86400+1020*60;
     }
   ts=(datetime)FPNYToServer(s,mode,gmt);te=(datetime)FPNYToServer(e,mode,gmt);
   return true;
  }
// What a row's window depends on: occurrences keep their data while it is unchanged.
uint FPPRowSig(FPPoint &p)
  {
   uint h=2166136261;
   h^=(uint)p.kind;h*=16777619;h^=(uint)p.sub;h*=16777619;h^=(uint)p.start;h*=16777619;h^=(uint)p.end;h*=16777619;
   h^=(uint)p.len;h*=16777619;h^=(uint)p.swing;h*=16777619;h^=(uint)p.look;h*=16777619;
   return h;
  }
void PPResetTaken(FPPOcc &o,const int kind)
  {
   // An open (and a period's close) is where price is when it forms: it is taken only
   // once price has left it and comes back.
   for(int q=0;q<FPP_PARTS;q++){o.tk[q]=0;o.away[q]=!((q==4 && (kind==FPPK_OPEN || kind==FPPK_GAP)) || (q==5 && kind==FPPK_PERIOD));}
   o.scan_to=0;
  }
void PPInitOcc(FPPOcc &o,const int row,FPPoint &p,const long key,const int age,const datetime ts,const datetime te,const datetime now)
  {
   o.row=row;o.uid=p.uid;o.key=key;o.age=age;o.state=0;o.sig=FPPRowSig(p);
   o.ts=ts;o.te=te;o.formed=0;o.future=ts>now;o.live=false;
   o.hi=0;o.lo=0;o.op=0;o.cl=0;o.th=0;o.tl=0;o.to=0;o.tc=0;o.dir=0;
   PPResetTaken(o,p.kind);
   PPApplyFlags(o);
  }
// Occurrences of every enabled row over its look-back. Data already read is kept for an
// occurrence whose row and window are unchanged, so a colour change re-reads nothing.
void PPBuild()
  {
   g_pocc_dirty=false;
   FPPOcc old[];
   int on=g_pocc_n;
   ArrayResize(old,on);
   for(int i=0;i<on;i++)old[i]=g_pocc[i];
   g_pocc_n=0;
   datetime now=ZoneNow();
   long td0=FPTradingDay(FPServerToNY((long)now,g_zmode,g_zgmt));
   g_pp_daykey=(int)td0;g_pp_mode=g_zmode;g_pp_gmt=g_zgmt;
   if(!g_pact.enabled)return;
   int hint=0;
   for(int r=0;r<g_pact.count;r++)
     {
      if(!g_pact.rows[r].enabled || !g_pact.group_on[g_pact.rows[r].group])continue;
      int cad=FPPCadence(g_pact.rows[r]);
      int want=cad==0?g_pact.days_back:(cad==1?g_pact.weeks_back:g_pact.months_back);
      long key=cad==0?td0:(cad==1?FPPWeekOf(td0):FPPMonthOf(td0));
      int made=0,guard=0;
      while(made<want && guard<400)
        {
         guard++;
         long k=key;
         if(cad==0){key--;if(FPDow(k)==0 || FPDow(k)==6)continue;}
         else key-=cad==1?7:1;
         int age=made++;
         datetime ts=0,te=0;
         if(!FPPWindow(g_pact.rows[r],k,g_pact.week_open,g_zmode,g_zgmt,ts,te))continue;
         if(g_pocc_n>=ArraySize(g_pocc))ArrayResize(g_pocc,g_pocc_n+256);
         int i=g_pocc_n++;
         PPInitOcc(g_pocc[i],r,g_pact.rows[r],k,age,ts,te,now);
         // Same order as last time, so the match is normally right at the hint.
         for(int c=0;c<on;c++)
           {
            int j=(hint+c)%on;
            if(old[j].uid!=g_pocc[i].uid || old[j].key!=k)continue;
            if(old[j].sig==g_pocc[i].sig && old[j].ts==ts && old[j].te==te && (old[j].state==1 || old[j].state==2))
              {
               g_pocc[i]=old[j];g_pocc[i].row=r;g_pocc[i].age=age;g_pocc[i].future=false;
               PPApplyFlags(g_pocc[i]);
              }
            hint=j+1;
            break;
           }
        }
     }
  }

// ---- reading prices from M1 (H1 for periods, refined to the minute)
// Candles of [from,to] from M1; for a stretch more than a day old that the terminal holds
// no M1 for (its M1 history ends at "Max bars in chart"), from M5. 0 none, -1 error.
int FPPCopy(const datetime from,const datetime to,const datetime now,MqlRates &r[])
  {
   int n=CopyRates(_Symbol,PERIOD_M1,from,to,r);
   if(n>0 || to>=now-86400)return n;
   int m=CopyRates(_Symbol,PERIOD_M5,from,to,r);
   return m>0?m:n;
  }
// The first M1 candle at or after `from`, within `span` seconds: 1 found, 0 none (yet), -1 error.
int FPPFirstBar(const datetime from,const long span,const datetime now,MqlRates &bar)
  {
   for(long a=0;a<span;a+=21600)
     {
      datetime s=from+(datetime)a,e=from+(datetime)(a+21600<span?a+21600:span)-1;
      if(s>now)return 0;
      if(e>now)e=now;
      MqlRates r[];
      int n=FPPCopy(s,e,now,r);
      if(n<0)return -1;
      if(n>0){bar=r[0];return 1;}
     }
   return 0;
  }
// The last M1 candle at or before `at` (M5 before the terminal's M1 history): 1 found, 0 none, -1 error.
int FPPLastBar(const datetime at,MqlRates &bar)
  {
   MqlRates r[];
   int n=CopyRates(_Symbol,PERIOD_M1,at,1,r);
   if(n<=0){int m=CopyRates(_Symbol,PERIOD_M5,at,1,r);if(m>0)n=m;}
   if(n<0)return -1;
   if(n==0)return 0;
   bar=r[n-1];return 1;
  }
// Minute of an hourly extreme: the M1 candle of that hour that made it (the hour when M1 is missing).
datetime FPPRefine(const datetime hour,const int side,const datetime from,const datetime stop)
  {
   datetime a=hour<from?from:hour,b=hour+3599;
   if(b>stop)b=stop;
   MqlRates m[];
   int n=CopyRates(_Symbol,PERIOD_M1,a,b,m);
   if(n<=0)n=CopyRates(_Symbol,PERIOD_M5,a,b,m);
   if(n<=0)return hour;
   int best=0;
   for(int k=1;k<n;k++)if(side>0?m[k].high>m[best].high:m[k].low<m[best].low)best=k;
   return m[best].time;
  }
// High and low of a window, with the M1 candle that made each (the first one, on a tie).
bool PPReadWindow(FPPOcc &o,const datetime now)
  {
   o.live=now<o.te;
   datetime stop=o.te-1;
   if(stop>now)stop=now;
   MqlRates r[];
   int n=FPPCopy(o.ts,stop,now,r);
   if(n<0){o.state=3;return false;}
   if(n==0){o.state=(o.live || now-stop<180)?3:2;return false;}
   double hi=r[0].high,lo=r[0].low;
   datetime th=r[0].time,tl=r[0].time;
   for(int k=1;k<n;k++){if(r[k].high>hi){hi=r[k].high;th=r[k].time;}if(r[k].low<lo){lo=r[k].low;tl=r[k].time;}}
   bool changed=o.state!=1 || hi!=o.hi || lo!=o.lo || th!=o.th || tl!=o.tl;
   o.hi=hi;o.lo=lo;o.th=th;o.tl=tl;o.op=r[0].open;o.to=r[0].time;o.cl=r[n-1].close;o.tc=r[n-1].time;
   o.formed=o.te;o.state=1;
   return changed;
  }
// Opening price: the first M1 candle of the hour from the set time.
bool PPReadOpen(FPPOcc &o,const datetime now)
  {
   o.live=false;
   MqlRates bar;
   int got=FPPFirstBar(o.ts,3600,now,bar);
   if(got<0){o.state=3;return false;}
   if(got==0){o.state=now<o.ts+3600?3:2;return false;}
   bool changed=o.state!=1 || o.op!=bar.open || o.to!=bar.time;
   o.op=bar.open;o.to=bar.time;o.hi=o.op;o.lo=o.op;o.th=o.to;o.tl=o.to;o.formed=o.to;o.state=1;
   return changed;
  }
// Gap: the close of the last candle at or before the close candle, and the first candle
// from the open time. The ORG close is the regular session's close of the prior session
// day (on a holiday, the session day before it).
bool PPReadGap(FPPOcc &o,FPPoint &p,const datetime now)
  {
   o.live=false;
   long span=p.sub==2?2*86400:3*3600;
   if(now<o.te){o.state=3;return false;}
   MqlRates c;
   int got=FPPLastBar(o.ts+59,c);
   if(p.sub==0 && got>0)
     {
      long day=FPFloorDiv(FPServerToNY((long)o.ts,g_zmode,g_zgmt),86400);
      for(int k=0;k<4 && got>0 && FPFloorDiv(FPServerToNY((long)c.time,g_zmode,g_zgmt),86400)!=day;k++)
        {
         day=FPPPrevWeekday(day);
         got=FPPLastBar((datetime)FPNYToServer(day*86400+(long)p.start*60,g_zmode,g_zgmt)+59,c);
        }
      if(got>0 && FPFloorDiv(FPServerToNY((long)c.time,g_zmode,g_zgmt),86400)!=day)got=0;
     }
   if(got<0){o.state=3;return false;}
   if(got==0){o.state=now-o.te<span?3:2;return false;}
   MqlRates b;
   int got_open=FPPFirstBar(o.te,span,now,b);
   if(got_open<0){o.state=3;return false;}
   if(got_open==0){o.state=now<o.te+(datetime)span?3:2;return false;}
   bool changed=o.state!=1 || o.op!=b.open || o.cl!=c.close || o.to!=b.time;
   o.cl=c.close;o.tc=c.time;o.op=b.open;o.to=b.time;
   o.dir=o.op>o.cl?1:(o.op<o.cl?-1:0);
   o.hi=MathMax(o.op,o.cl);o.lo=MathMin(o.op,o.cl);o.th=o.tc;o.tl=o.tc;o.formed=o.to;o.state=1;
   return changed;
  }
// First M1 fair value gap of the window: the middle candle and the newest candle open inside
// it (the oldest may be before it). Only closed candles count.
bool PPReadFvg(FPPOcc &o,const datetime now)
  {
   datetime limit=o.te,cur=(datetime)(((long)now/60)*60);
   if(cur<limit)limit=cur;
   o.live=now<o.te;
   if(limit<=o.ts){o.state=3;return false;}
   MqlRates b[];
   int n=CopyRates(_Symbol,PERIOD_M1,o.ts-180,limit-1,b);
   if(n<0){o.state=3;return false;}
   for(int i=2;i<n;i++)
     {
      if(b[i].time<o.ts)continue;
      if(b[i].time>=limit)break;
      if(b[i-1].time<o.ts)continue;
      bool bull=b[i-2].high<b[i].low,bear=b[i-2].low>b[i].high;
      if(!bull && !bear)continue;
      o.hi=bull?b[i].low:b[i-2].low;o.lo=bull?b[i-2].high:b[i].high;o.dir=bull?1:-1;
      o.th=b[i-2].time;o.tl=o.th;o.to=o.th;o.formed=b[i].time+60;o.state=1;o.live=false;
      return true;
     }
   o.state=limit>=o.te?2:3;
   return false;
  }
// First M1 order block of the window: the first close beyond a swing high/low formed in
// the window (up to `look` minutes after it) is the break; the order block is the last
// opposite candle before it that opens in the window.
bool PPReadOb(FPPOcc &o,FPPoint &p,const datetime now)
  {
   int w=Lim(p.swing,1,5);
   datetime bos_end=o.te+(datetime)(Lim(p.look,0,60)*60),cur=(datetime)(((long)now/60)*60);
   datetime limit=bos_end<cur?bos_end:cur;
   o.live=now<bos_end;
   if(limit<=o.ts){o.state=3;return false;}
   MqlRates b[];
   int n=CopyRates(_Symbol,PERIOD_M1,o.ts-(datetime)(w*60)-120,limit-1,b);
   if(n<0){o.state=3;return false;}
   if(n<=2*w){o.state=limit>=bos_end?2:3;return false;}
   int sh[];
   int sl[];
   ArrayResize(sh,n);ArrayResize(sl,n);
   for(int s=0;s<n;s++){sh[s]=0;sl[s]=0;}
   for(int s=w;s<n-w;s++)
     {
      bool is_h=true,is_l=true;
      for(int k=1;k<=w && (is_h || is_l);k++)
        {
         if(b[s-k].high>=b[s].high || b[s+k].high>=b[s].high)is_h=false;
         if(b[s-k].low<=b[s].low || b[s+k].low<=b[s].low)is_l=false;
        }
      sh[s]=is_h?1:0;sl[s]=is_l?1:0;
     }
   int lsh=-1,lsl=-1;
   for(int i=0;i<n;i++)
     {
      int s=i-1;
      if(s>=0 && b[s].time>=o.ts && b[s].time<o.te){if(sh[s]!=0)lsh=s;if(sl[s]!=0)lsl=s;}
      if(b[i].time<o.ts)continue;
      if(b[i].time>=limit)break;
      bool bull=lsh>=0 && b[i].close>b[lsh].high;
      bool bear=!bull && lsl>=0 && b[i].close<b[lsl].low;
      if(!bull && !bear)continue;
      for(int j=i-1;j>=0;j--)
        {
         if(b[j].time<o.ts)break;
         if(b[j].time>=o.te)continue;
         if(bull?b[j].close>=b[j].open:b[j].close<=b[j].open)continue;
         o.hi=b[j].high;o.lo=b[j].low;o.dir=bull?1:-1;o.th=b[j].time;o.tl=o.th;o.to=o.th;
         o.formed=b[i].time+60;o.state=1;o.live=false;
         return true;
        }
      o.state=2;o.live=false;   // the first break has no order block in the window: none today
      return false;
     }
   o.state=limit>=bos_end?2:3;
   return false;
  }
// Period open/high/low/close from H1 candles; the high, low and open refined to the minute.
bool PPReadPeriod(FPPOcc &o,const datetime now)
  {
   o.live=now<o.te;
   datetime stop=o.te-1;
   if(stop>now)stop=now;
   MqlRates r[];
   int n=CopyRates(_Symbol,PERIOD_H1,o.ts,stop,r);
   if(n<0){o.state=3;return false;}
   if(n==0){o.state=(o.live || now-stop<3600)?3:2;return false;}
   double hi=r[0].high,lo=r[0].low;
   datetime th=r[0].time,tl=r[0].time;
   for(int k=1;k<n;k++){if(r[k].high>hi){hi=r[k].high;th=r[k].time;}if(r[k].low<lo){lo=r[k].low;tl=r[k].time;}}
   th=FPPRefine(th,1,o.ts,stop);tl=FPPRefine(tl,-1,o.ts,stop);
   MqlRates first;
   datetime to=r[0].time;
   if(FPPFirstBar(r[0].time<o.ts?o.ts:r[0].time,3600,now,first)>0)to=first.time;
   bool changed=o.state!=1 || hi!=o.hi || lo!=o.lo || th!=o.th || tl!=o.tl || r[n-1].close!=o.cl;
   o.hi=hi;o.lo=lo;o.th=th;o.tl=tl;o.op=r[0].open;o.to=to;o.cl=r[n-1].close;o.tc=o.te;
   o.formed=o.te;o.state=1;
   return changed;
  }
// Reads one occurrence; true when its prices changed.
bool PPRead(const int i,const datetime now)
  {
   if(g_pocc[i].future){if(now<g_pocc[i].ts)return false;g_pocc[i].future=false;g_pocc[i].state=0;}
   int r=g_pocc[i].row;
   if(r<0 || r>=g_pact.count)return false;
   int kind=g_pact.rows[r].kind;
   bool was=g_pocc[i].state==1;
   double hi=g_pocc[i].hi,lo=g_pocc[i].lo;
   bool changed=false;
   if(kind==FPPK_WINDOW)changed=PPReadWindow(g_pocc[i],now);
   else if(kind==FPPK_OPEN)changed=PPReadOpen(g_pocc[i],now);
   else if(kind==FPPK_GAP)changed=PPReadGap(g_pocc[i],g_pact.rows[r],now);
   else if(kind==FPPK_FVG)changed=PPReadFvg(g_pocc[i],now);
   else if(kind==FPPK_OB)changed=PPReadOb(g_pocc[i],g_pact.rows[r],now);
   else changed=PPReadPeriod(g_pocc[i],now);
   // New levels: the taken scan starts again.
   if(g_pocc[i].state==1 && (!was || hi!=g_pocc[i].hi || lo!=g_pocc[i].lo))PPResetTaken(g_pocc[i],kind);
   return changed;
  }

// ---- taken: the first candle after a level formed that trades through it
// 1 taken by trading above it (a high), -1 below it (a low), 0 by reaching it.
int FPPRule(const int kind,const int part)
  {
   if(kind==FPPK_WINDOW || kind==FPPK_PERIOD){if(part==0)return 1;if(part==1)return -1;}
   return 0;
  }
double FPPLevel(FPPOcc &o,const int part)
  {
   if(part==0)return o.hi;
   if(part==1)return o.lo;
   if(part==2)return (o.hi+o.lo)/2.0;
   if(part==4)return o.op;
   if(part==5)return o.cl;
   if(part>=6)return o.lo+(o.hi-o.lo)*FPPFrac(part);
   return 0;
  }
// The part whose taking fills a zone: a gap's close, the far edge of an FVG or OB.
int FPPFarPart(FPPOcc &o,const int kind)
  {
   if(kind==FPPK_GAP)return 5;
   if(kind==FPPK_FVG || kind==FPPK_OB)return o.dir>0?1:0;
   return -1;
  }
bool FPPAllTaken(FPPOcc &o,const int kind)
  {
   int m=FPPTakeable(kind);
   for(int q=0;q<FPP_PARTS;q++)if(q!=3 && (m&(1<<q))!=0 && o.tk[q]==0)return false;
   return true;
  }
// One candle against every part not taken yet; true when it took one.
bool PPTakeBar(FPPOcc &o,const int kind,const double high,const double low,const datetime t)
  {
   bool any=false;
   int m=FPPTakeable(kind);
   for(int q=0;q<FPP_PARTS;q++)
     {
      if(q==3 || (m&(1<<q))==0 || o.tk[q]!=0)continue;
      double v=FPPLevel(o,q);
      int rule=FPPRule(kind,q);
      bool hit=false;
      if(rule>0)hit=high>v;
      else if(rule<0)hit=low<v;
      else
        {
         bool inside=low<=v && v<=high;
         if(!o.away[q]){if(!inside)o.away[q]=true;}
         else hit=inside;
        }
      if(hit){o.tk[q]=t;any=true;}
     }
   int edge=FPPFarPart(o,kind);
   if(edge>=0)o.tk[3]=o.tk[edge];
   return any;
  }
// Catches up the taken scan of one occurrence: M1 for the three days after it formed (at
// least one trading day, weekend or not) and for the last day, H1 in between (a hit is
// found again to the minute in its hour).
bool PPScan(FPPOcc &o,const int kind,const datetime now)
  {
   if(o.state!=1 || o.live || FPPAllTaken(o,kind))return false;
   datetime from=o.scan_to>0?o.scan_to:o.formed;
   if(from>now)return false;
   datetime m1_end=(datetime)((((long)o.formed+3*86400+3599)/3600)*3600);
   datetime recent=(datetime)((((long)now-86400)/3600)*3600);
   bool changed=false;
   if(from<m1_end || from>=recent)
     {
      datetime stop=from<m1_end?m1_end-1:now;
      if(stop>now)stop=now;
      MqlRates r[];
      int n=FPPCopy(from,stop,now,r);
      if(n<0)return false;
      for(int k=0;k<n;k++)if(PPTakeBar(o,kind,r[k].high,r[k].low,r[k].time))changed=true;
      if(n>0)o.scan_to=r[n-1].time+60>now?r[n-1].time:r[n-1].time+60;   // the forming candle is read again
      else if(stop<now-3600)o.scan_to=stop+1;
      return changed;
     }
   datetime stop=from+30*86400;
   if(stop>recent)stop=recent;
   stop--;
   MqlRates h[];
   int n=CopyRates(_Symbol,PERIOD_H1,from,stop,h);
   if(n<0)return false;
   for(int k=0;k<n;k++)
     {
      FPPOcc probe=o;
      if(!PPTakeBar(probe,kind,h[k].high,h[k].low,h[k].time)){o=probe;continue;}
      MqlRates m[];
      int mn=CopyRates(_Symbol,PERIOD_M1,h[k].time<from?from:h[k].time,h[k].time+3599,m);
      if(mn<=0)mn=CopyRates(_Symbol,PERIOD_M5,h[k].time<from?from:h[k].time,h[k].time+3599,m);
      for(int j=0;j<mn;j++)PPTakeBar(o,kind,m[j].high,m[j].low,m[j].time);
      // Anything the hour took that its minutes did not show (missing M1): the hour.
      for(int q=0;q<FPP_PARTS;q++)if(o.tk[q]==0 && probe.tk[q]!=0){o.tk[q]=probe.tk[q];o.away[q]=true;}
      changed=true;
      if(FPPAllTaken(o,kind)){o.scan_to=h[k].time+3600;return true;}
     }
   o.scan_to=n>0?h[n-1].time+3600:stop+1;
   return changed;
  }
uint FPPHash(const string s)
  {uint h=2166136261;for(int i=0;i<StringLen(s);i++){h^=(uint)StringGetCharacter(s,i);h*=16777619;}return h;}
// One alert per level across every chart of this workspace: the first chart to flip the
// terminal-wide flag sends it.
bool PPAlertClaim(const uint uid,const long key,const int part)
  {
   string id="FPP."+WorkspaceTag()+"."+IntegerToString((long)FPPHash(_Symbol+"|"+IntegerToString((long)uid)+"|"+IntegerToString(key)+"|"+IntegerToString(part)));
   GlobalVariableTemp(id);
   return GlobalVariableSetOnCondition(id,1.0,0.0);
  }
void PPFireAlert(const string what,const double price,const bool test)
  {
   string msg=test?"Fibonacci Pro: price points test alert ("+_Symbol+")":"Fibonacci Pro: "+_Symbol+" took "+what+" at "+DoubleToString(price,_Digits);
   if(g_pact.alert_sound)PlaySound("alert.wav");
   if(g_pact.alert_push && !SendNotification(msg))
      Print("Fibonacci Pro: push notification not sent. Enable it in Tools > Options > Notifications with your MetaQuotes ID.");
   Print(msg);Status(msg);
  }
// Alerts for levels of an alert row that price has just taken (in the last 3 minutes):
// each line once, and a zone once when it is filled.
void PPAlerts(const int i,FPPOcc &prev,const datetime now)
  {
   int row=g_pocc[i].row;
   if(row<0 || row>=g_pact.count || !g_pact.rows[row].alert || (!g_pact.alert_sound && !g_pact.alert_push))return;
   int kind=g_pact.rows[row].kind,shown=g_pact.rows[row].parts&FPPAllowed(kind),edge=FPPFarPart(g_pocc[i],kind);
   for(int q=0;q<FPP_PARTS;q++)
     {
      if(q==3 || prev.tk[q]!=0 || g_pocc[i].tk[q]==0 || g_pocc[i].tk[q]<now-180)continue;
      bool fill=q==edge && (shown&FPPP_BOX)!=0;
      if((shown&FPPBitOf(q))==0 && !fill)continue;
      if(!PPAlertClaim(g_pocc[i].uid,g_pocc[i].key,q))continue;
      PPFireAlert(fill?g_pact.rows[row].name+" (filled)":FPPPartName(g_pact.rows[row],q),FPPLevel(g_pocc[i],q),false);
     }
  }
// A catch-up scan step, with alerts for what it finds.
bool PPScanAlert(const int i,const datetime now)
  {
   int row=g_pocc[i].row;
   if(row<0 || row>=g_pact.count)return false;
   FPPOcc prev=g_pocc[i];
   bool changed=PPScan(g_pocc[i],g_pact.rows[row].kind,now);
   PPAlerts(i,prev,now);
   return changed;
  }
// Levels taken by the newest candles: one shared M1 read for every occurrence whose scan
// is up to date.
bool PPTail(const datetime now)
  {
   datetime start=(datetime)(((long)now/60)*60-120);
   MqlRates r[];
   int n=CopyRates(_Symbol,PERIOD_M1,start,now,r);
   if(n<=0)return false;
   bool changed=false;
   for(int i=0;i<g_pocc_n;i++)
     {
      int row=g_pocc[i].row;
      if(row<0 || row>=g_pact.count || g_pocc[i].state!=1 || g_pocc[i].live || g_pocc[i].scan_to<start)continue;
      int kind=g_pact.rows[row].kind;
      if(FPPAllTaken(g_pocc[i],kind))continue;
      FPPOcc prev=g_pocc[i];
      bool took=false;
      for(int k=0;k<n;k++)
         if(r[k].time>=g_pocc[i].scan_to && PPTakeBar(g_pocc[i],kind,r[k].high,r[k].low,r[k].time))took=true;
      if(r[n-1].time>g_pocc[i].scan_to)g_pocc[i].scan_to=r[n-1].time;
      if(!took)continue;
      changed=true;
      PPAlerts(i,prev,now);
     }
   return changed;
  }
// Once a second: day roll-over, live windows, waiting gaps and patterns, taken levels,
// alerts, settings from other charts.
void PPTick(const ulong tick)
  {
   if(tick-g_pp_tick<1000)return;
   g_pp_tick=tick;
   datetime now=ZoneNow();
   long td0=FPTradingDay(FPServerToNY((long)now,g_zmode,g_zgmt));
   if(g_pocc_dirty || td0!=g_pp_daykey || g_zmode!=g_pp_mode || g_zgmt!=g_pp_gmt){PPBuild();g_dirty=true;}
   if(tick-g_pp_poll>=2000){g_pp_poll=tick;PPPollShared();}
   if(!g_pact.enabled || g_pocc_n==0)return;
   bool retry=tick-g_pp_retry>=30000;
   if(retry)g_pp_retry=tick;
   int reads=12,scans=8;
   for(int k=0;k<g_pocc_n;k++)
     {
      int i=(g_pp_rr+k)%g_pocc_n;
      if(retry && (g_pocc[i].state==2 || g_pocc[i].state==3))g_pocc[i].state=0;
      bool refresh=g_pocc[i].live || (g_pocc[i].future && now>=g_pocc[i].ts) || g_pocc[i].state==3 || g_pocc[i].state==0;
      if(refresh && reads>0){reads--;if(PPRead(i,now))g_dirty=true;}
      int row=g_pocc[i].row;
      if(g_pocc[i].state==1 && !g_pocc[i].live && scans>0 && row>=0 && row<g_pact.count && g_pocc[i].scan_to<(datetime)(((long)now/60)*60-120))
        {scans--;if(PPScanAlert(i,now))g_dirty=true;}
     }
   g_pp_rr=(g_pp_rr+7)%g_pocc_n;
   if(PPTail(now))g_dirty=true;
  }

// ---- price points on the chart: lines, zones, labels, arrows, hover and selection
// Ray back as set for the whole occurrence (1.67, 1.68), else the row's default.
bool FPPRay(FPPOcc &o,FPPoint &p){if((o.flags&1)!=0)return true;if((o.flags&2)!=0)return false;return p.ray;}
// What one line of an occurrence does: as set for that line (a gap, FVG or OB: for the
// zone, index 3), else as set for the whole occurrence, else the row's default.
int FPPTarget(const int kind,const int part){return FPPZoneKind(kind)?3:part;}
bool FPPRayBackAt(FPPOcc &o,FPPoint &p,const int part)
  {
   int f=o.pflags[FPPTarget(p.kind,part)];
   if((f&1)!=0)return true;
   if((f&2)!=0)return false;
   return FPPRay(o,p);
  }
bool FPPRayFwdAt(FPPOcc &o,FPPoint &p,const int part){return ((o.pflags[FPPTarget(p.kind,part)]|o.flags)&8)!=0;}
bool FPPHiddenAt(FPPOcc &o,FPPoint &p,const int part){return ((o.pflags[FPPTarget(p.kind,part)]|o.flags)&4)!=0;}
datetime FPPEndAt(FPPOcc &o,FPPoint &p,const int part){return o.pend[FPPTarget(p.kind,part)];}
// Any line rayed back: the occurrence reaches into the past, so it is never culled.
bool FPPRayedAny(FPPOcc &o,FPPoint &p)
  {
   if(FPPRay(o,p))return true;
   for(int q=0;q<FPP_PARTS;q++)if((o.pflags[q]&1)!=0)return true;
   return false;
  }
// How a row's taken levels end: -1 they don't (they run on), 0 at the candle that took them,
// 1 at the end of that trading day (17:00 New York), 2 at the end of that week (Friday 17:00).
int FPPEndMode(FPPoint &p)
  {
   if(p.ends==2)return -1;
   if(p.ends==1)return 0;
   if(p.ends==3)return 1;
   if(p.ends==4)return 2;
   return g_pact.end_taken?Lim(g_pact.taken_end,0,2):-1;
  }
// Where a level taken at `t` ends: the take itself, or the end of its trading day or week.
datetime FPPTakenEnd(const datetime t,const int mode)
  {
   if(mode<=0)return t;
   long td=FPTradingDay(FPServerToNY((long)t,g_zmode,g_zgmt));
   if(mode==2)td=FPPWeekOf(td)+4;
   return (datetime)FPNYToServer(td*86400+1020*60,g_zmode,g_zgmt);
  }
// The x a taken line ends at: its end, or the right edge while that end is still to come.
bool FPPTakenX(const datetime t,const int mode,const double v,const datetime now,int &x)
  {
   datetime e=FPPTakenEnd(t,mode);
   if(mode>0 && e>now){x=g_width-1;return true;}
   int ignore=0;
   return XY(e,v,x,ignore);
  }
bool FPPBold(FPPoint &p){return p.bold==1 || (p.bold==0 && g_pact.label_bold);}
// The candle each part starts from.
datetime FPPAnchor(FPPOcc &o,const int kind,const int part)
  {
   if(kind==FPPK_FVG || kind==FPPK_OB)return o.th;
   if(kind==FPPK_GAP)return (part==5 || part==3)?o.tc:o.to;
   if(kind==FPPK_OPEN)return o.to;
   if(part==0)return o.th;
   if(part==1)return o.tl;
   if(part==4)return o.to;
   if(part==3)return o.ts;
   return o.te;   // a close or CE: when the window or period ended
  }
// Line style by role: opens dashed, closes solid, highs dash-dot-dot, lows dash-dot, CE,
// quadrants and octants dotted; the edges of gaps, FVGs and OBs solid.
int FPPRoleStyle(const int kind,const int part)
  {
   if(part==2 || part>=6)return STYLE_DOT;
   if(kind==FPPK_GAP || kind==FPPK_FVG || kind==FPPK_OB)return STYLE_SOLID;
   if(part==4)return STYLE_DASH;
   if(part==5)return STYLE_SOLID;
   return part==0?STYLE_DASHDOTDOT:STYLE_DASHDOT;
  }
int FPPStyle(FPPoint &p,const int part){return p.style<0?FPPRoleStyle(p.kind,part):Lim(p.style,0,4);}
// Zone shade: order blocks lighter, fair value gaps darker (or one shade for both).
color FPPZoneInk(FPPoint &p)
  {
   if(g_pact.tint==1 || p.kind==FPPK_GAP)return p.ink;
   return p.kind==FPPK_OB?FPBlend(p.ink,clrWhite,0.35):FPBlend(p.ink,clrBlack,0.3);
  }
string FPPArrow(const int dir)
  {
   if(dir>0)return " "+Glyph(0x25B2);
   if(dir<0)return " "+Glyph(0x25BC);
   return "";
  }
bool FPPZoneKind(const int kind){return kind==FPPK_GAP || kind==FPPK_FVG || kind==FPPK_OB;}
bool FPPWeekly(FPPoint &p){return (p.kind==FPPK_GAP && p.sub==2) || (p.kind==FPPK_PERIOD && p.sub==1);}
// Short day of an occurrence for labels: "Tue 17", "wk 16.11", "Nov 2026".
string FPPWhen(FPPOcc &o,FPPoint &p)
  {
   if(p.kind==FPPK_PERIOD && p.sub==2)
     {
      string mn[]={"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
      return mn[(int)(o.key%12)]+" "+IntegerToString(o.key/12);
     }
   int y=0,m=0,d=0;
   FPCivilFromDays(o.key,y,m,d);
   if(FPPWeekly(p))return "wk "+FPTwo(d)+"."+FPTwo(m);
   return g_dow_names[FPDow(o.key)]+" "+FPTwo(d);
  }
// Label mode of a row: 0 name, 1 name + day, 2 name + price, 3 off.
int FPPLabelMode(FPPoint &p){return p.label>0?Lim(p.label-1,0,3):g_pact.label_mode;}
string FPPLabelText(FPPOcc &o,FPPoint &p,const int part)
  {
   int mode=FPPLabelMode(p);
   if(mode==3)return "";
   if(part>=6)   // a quadrant or octant: just its share of the range (hover names it)
     {
      string pct=FPPPct(part);
      if(mode==2)pct+=" "+DoubleToString(FPPLevel(o,part),_Digits);
      return pct;
     }
   string t=FPPPartName(p,part);
   if(part==3 && FPPZoneKind(p.kind))t+=FPPArrow(o.dir);
   if(mode==1)t+=" "+FPPWhen(o,p);
   else if(mode==2)t+=" "+DoubleToString(part==3?(o.dir<0?o.lo:o.hi):FPPLevel(o,part),_Digits);
   return t;
  }
void PPAddLine(const int occ,const int part,const int x0,const int x1,const int y,const int style,const int width,const color ink,const uchar alpha,const bool taken,const bool sel)
  {
   if(g_ppline_n>=ArraySize(g_ppline))ArrayResize(g_ppline,g_ppline_n+128);
   int k=g_ppline_n++;
   g_ppline[k].occ=occ;g_ppline[k].part=part;g_ppline[k].x0=x0;g_ppline[k].x1=x1;g_ppline[k].y=y;
   g_ppline[k].style=style;g_ppline[k].width=width;g_ppline[k].ink=ink;g_ppline[k].alpha=alpha;g_ppline[k].taken=taken;g_ppline[k].sel=sel;
  }
void PPAddBox(const int occ,const int x0,const int x1,const int y0,const int y1,const color ink,const uchar alpha,const bool zone)
  {
   if(g_ppbox_n>=ArraySize(g_ppbox))ArrayResize(g_ppbox,g_ppbox_n+32);
   int k=g_ppbox_n++;
   g_ppbox[k].occ=occ;g_ppbox[k].x0=x0;g_ppbox[k].x1=x1;g_ppbox[k].y0=y0;g_ppbox[k].y1=y1;g_ppbox[k].ink=ink;g_ppbox[k].alpha=alpha;g_ppbox[k].zone=zone;
  }
void PPAddFill(const int x0,const int x1,const int y0,const int y1,const color ink,const double a)
  {
   if(a<=0)return;
   if(g_ppfill_n>=ArraySize(g_ppfill))ArrayResize(g_ppfill,g_ppfill_n+32);
   FPLayerSet(g_ppfill[g_ppfill_n],x0,x1,y0,y1,ink,ink,a,a,2);   // neutral: neither cut by zones nor cutting Fibs
   g_ppfill_n++;
  }
// A level above or below the visible prices: an arrow at the chart's edge.
void PPAddOff(const int occ,const int part,const int y)
  {
   if(!g_pact.offscreen)return;
   if(g_ppoff_n>=ArraySize(g_ppoff))ArrayResize(g_ppoff,g_ppoff_n+32);
   g_ppoff[g_ppoff_n].occ=occ;g_ppoff[g_ppoff_n].part=part;g_ppoff[g_ppoff_n].y=y;g_ppoff_n++;
  }
// Lines, zones and fills of one occurrence, in screen coordinates. Each line can be rayed
// back to the chart's first candle, rayed forward to the right edge, ended by hand or hidden.
void PPAddOcc(const int i,const datetime now)
  {
   int r=g_pocc[i].row,kind=g_pact.rows[r].kind;
   int parts=g_pact.rows[r].parts&FPPAllowed(kind);
   int mode=FPPEndMode(g_pact.rows[r]),psel=i==g_psel?FPPTarget(kind,g_psel_part):-1;
   bool live=g_pocc[i].live;
   bool zone=FPPZoneKind(kind) && (parts&FPPP_BOX)!=0;
   color ink=g_pact.rows[r].ink;
   int width=Lim(g_pact.rows[r].width,1,5),ignore=0;
   for(int q=0;q<FPP_PARTS;q++)
     {
      if(q==3 || (parts&FPPBitOf(q))==0)continue;
      if(live && (q==2 || q>=5))continue;          // known once the window or period has ended
      if(FPPHiddenAt(g_pocc[i],g_pact.rows[r],q))continue;
      bool sel=FPPTarget(kind,q)==psel,fwd=FPPRayFwdAt(g_pocc[i],g_pact.rows[r],q);
      datetime hand=FPPEndAt(g_pocc[i],g_pact.rows[r],q);
      double v=FPPLevel(g_pocc[i],q);
      int x0=0,x1=g_width-1,y=0;
      if(!XY(FPPAnchor(g_pocc[i],kind,q),v,x0,y))continue;
      if(FPPRayBackAt(g_pocc[i],g_pact.rows[r],q))x0=(int)MathMin(x0,g_pp_first_x);   // back to the chart's first candle
      bool taken=mode>=0 && !live && g_pocc[i].tk[q]!=0;
      if(taken && g_pact.taken_show==1 && !sel && !fwd && hand==0)continue;   // hidden once taken, unless extended
      if(fwd)x1=g_width-1;
      else if(hand>0){if(!XY(hand,v,x1,ignore))continue;if(x1<x0)x1=x0;}
      else if(taken)
        {
         if(!FPPTakenX(g_pocc[i].tk[q],mode,v,now,x1))continue;
         if(x1<x0)x1=x0;
        }
      if(x1<0 || x0>=g_width)continue;
      if(y<0 || y>=g_height){if(!taken)PPAddOff(i,q,y);continue;}
      // Quadrants a little lighter than the other lines, octants lighter still.
      int base=q>=8?150:(q>=6?200:255);
      uchar alpha=(uchar)((taken && g_pact.taken_show==0 && !sel)?base*90/255:(sel?255:base));
      PPAddLine(i,q,x0,x1,y,FPPStyle(g_pact.rows[r],q),sel?width+1:width,ink,alpha,taken,sel);
     }
   if((parts&FPPP_BOX)==0 || FPPHiddenAt(g_pocc[i],g_pact.rows[r],3))return;
   bool sel=psel==3,fwd=FPPRayFwdAt(g_pocc[i],g_pact.rows[r],3),back=FPPRayBackAt(g_pocc[i],g_pact.rows[r],3);
   datetime hand=FPPEndAt(g_pocc[i],g_pact.rows[r],3);
   if(kind==FPPK_WINDOW)
     {
      // The window's range: a rectangle from its start to its end.
      int x0=0,x1=0,yh=0,yl=0;
      datetime end=live?now:g_pocc[i].te;
      if(!ZoneX(g_pocc[i].ts,x0) || !ZoneX(end,x1) || !XY(g_pocc[i].ts,g_pocc[i].hi,ignore,yh) || !XY(g_pocc[i].ts,g_pocc[i].lo,ignore,yl))return;
      if(back)x0=(int)MathMin(x0,g_pp_first_x);
      if(fwd)x1=g_width-1;
      else if(hand>0){if(!ZoneX(hand,x1))return;if(x1<x0)x1=x0;}
      if(x1<0 || x0>=g_width || yl<0 || yh>=g_height)return;
      PPAddBox(i,x0,x1,yh,yl,ink,(uchar)(sel?255:160),false);
      if(g_pact.range_fill)PPAddFill(x0,x1-1,yh,yl,ink,g_pact.opacity/100.0*0.6);
      return;
     }
   if(!zone || g_pocc[i].hi<=g_pocc[i].lo)return;
   int x0=0,x1=g_width-1,y0=0,y1=0;
   datetime a=FPPAnchor(g_pocc[i],kind,3);
   if(!XY(a,g_pocc[i].hi,x0,y0) || !XY(a,g_pocc[i].lo,ignore,y1))return;
   if(back)x0=(int)MathMin(x0,g_pp_first_x);
   bool filled=mode>=0 && g_pocc[i].tk[3]!=0;
   if(filled && g_pact.taken_show==1 && !sel && !fwd && hand==0)return;
   if(fwd)x1=g_width-1;
   else if(hand>0){if(!XY(hand,g_pocc[i].hi,x1,ignore))return;if(x1<x0)x1=x0;}
   else if(filled)
     {
      if(!FPPTakenX(g_pocc[i].tk[3],mode,g_pocc[i].hi,now,x1))return;
      if(x1<x0)x1=x0;
     }
   if(x1<0 || x0>=g_width || y1<0 || y0>=g_height)return;
   double dim=(filled && g_pact.taken_show==0 && !sel)?0.4:1.0;
   PPAddBox(i,x0,x1,y0,y1,ink,(uchar)MathRound(255*dim),true);
   if(g_pact.fill)PPAddFill(x0,x1,y0,y1,FPPZoneInk(g_pact.rows[r]),g_pact.opacity/100.0*dim);
  }
// Screen data of this frame (reused by hover and clicks) and the fill layers. Prices are
// read and taken levels scanned here too, a few per frame, nearest the view first.
void PPPrepare()
  {
   g_ppline_n=0;g_ppbox_n=0;g_ppfill_n=0;g_ppoff_n=0;g_psel=-1;
   if(g_pocc_dirty || g_zmode!=g_pp_mode || g_zgmt!=g_pp_gmt)PPBuild();
   // Rayed levels reach back to the oldest candle the chart has on its timeframe.
   g_pp_first_x=-1000000;
   int nb=iBars(_Symbol,(ENUM_TIMEFRAMES)_Period);
   if(nb>0)
     {
      datetime first=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,nb-1);
      int fx=0,fy=0;
      if(first>0 && XY(first,g_view_max,fx,fy))g_pp_first_x=fx;
     }
   if(g_pact.enabled && g_pocc_n>0)
     {
      datetime now=ZoneNow();
      datetime tail=(datetime)(((long)now/60)*60-120);
      int budget=30;
      bool more=false,progress=false;
      for(int i=0;i<g_pocc_n;i++)
        {
         int r=g_pocc[i].row;
         if(r<0 || r>=g_pact.count)continue;
         if(g_pocc[i].uid==g_psel_uid && g_pocc[i].key==g_psel_key)g_psel=i;
         if(g_tf>g_pact.group_tf[g_pact.rows[r].group] || (g_pocc[i].flags&4)!=0)continue;
         if(g_cull_ok && g_pocc[i].ts-180>g_vt1 && !FPPRayedAny(g_pocc[i],g_pact.rows[r]))continue;   // a rayed level reaches into the past
         if(g_pocc[i].state==0 || (g_pocc[i].future && now>=g_pocc[i].ts))
           {
            if(budget>0){budget--;int before=g_pocc[i].state;PPRead(i,now);if(g_pocc[i].state!=before)progress=true;}
            else more=true;
           }
         if(g_pocc[i].state!=1)continue;
         int kind=g_pact.rows[r].kind;
         if(!g_pocc[i].live && g_pocc[i].scan_to<tail && !FPPAllTaken(g_pocc[i],kind))
           {
            if(budget>0){budget--;datetime before=g_pocc[i].scan_to;PPScanAlert(i,now);if(g_pocc[i].scan_to!=before)progress=true;}
            else more=true;
           }
         PPAddOcc(i,now);
        }
      // Keep going next frame only while the work moves forward (a closed market adds no bars).
      if(more && progress)g_dirty=true;
     }
   if(g_psel_uid!=0 && g_psel<0){g_psel_uid=0;g_psel_key=0;g_psel_part=-1;g_ui_dirty=true;}
   ulong sig=FPMix((ulong)1469598103934665603,g_ppfill_n);
   for(int k=0;k<g_ppfill_n;k++)
     {
      sig=FPMix(sig,g_ppfill[k].x0);sig=FPMix(sig,g_ppfill[k].x1);sig=FPMix(sig,g_ppfill[k].y0);sig=FPMix(sig,g_ppfill[k].y1);
      sig=FPMix(sig,(long)g_ppfill[k].ink);sig=FPMix(sig,(long)MathRound(g_ppfill[k].a0*1000));
     }
   g_ppfill_sig=sig;
  }
// Price point zones and ranges join the background shading after the session zones.
int PPShade(FPLayer &layers[],const int n)
  {
   int m=n;
   for(int k=0;k<g_ppfill_n;k++)layers[m++]=g_ppfill[k];
   return m;
  }
void PPAddLabel(const int x,const int y,const int w,const int h,const int line,const string text,const color ink,const uchar alpha,const bool bold)
  {
   if(g_pplabel_n>=ArraySize(g_pplabel))ArrayResize(g_pplabel,g_pplabel_n+64);
   int k=g_pplabel_n++;
   g_pplabel[k].x=x;g_pplabel[k].y=y;g_pplabel[k].w=w;g_pplabel[k].h=h;g_pplabel[k].line=line;
   g_pplabel[k].text=text;g_pplabel[k].ink=ink;g_pplabel[k].alpha=alpha;g_pplabel[k].bold=bold;
  }
// The label font, bold or regular (set only when it changes).
void PPFont(const bool bold)
  {
   int want=bold?1:0;
   if(want==g_pp_font)return;
   g_line_canvas.FontSet("Segoe UI",g_pact.label_size,bold?FW_BOLD:0);
   g_pp_font=want;
  }
// Labels: at the end of each line (right edge while untaken), zone names at their top-left,
// names pinned at the left edge for lines that start off-screen; same-price names merged,
// then each label moved down until it clears the ones above it.
void PPLayoutLabels()
  {
   g_pplabel_n=0;
   int th=g_line_canvas.TextHeight("Ag");
   for(int k=0;k<g_ppline_n;k++)
     {
      int i=g_ppline[k].occ,r=g_pocc[i].row,q=g_ppline[k].part;
      int kind=g_pact.rows[r].kind;
      if(FPPZoneKind(kind) && (g_pact.rows[r].parts&FPPP_BOX)!=0 && g_pocc[i].hi>g_pocc[i].lo)continue;   // the zone's name stands for it
      string t=FPPLabelText(g_pocc[i],g_pact.rows[r],q);
      if(StringLen(t)==0)continue;
      bool bold=FPPBold(g_pact.rows[r]);
      PPFont(bold);
      int tw=g_line_canvas.TextWidth(t);
      int x=Lim(g_ppline[k].x1-tw-4,2,(int)MathMax(2,g_width-tw-2));
      PPAddLabel(x,g_ppline[k].y-th-1,tw,th,k,t,g_ppline[k].ink,g_ppline[k].alpha,bold);
      if(g_pact.pin_left && g_ppline[k].x0<=0 && g_ppline[k].x1>tw+60)
        {
         string pin=q>=6?t:FPPPartName(g_pact.rows[r],q);
         PPAddLabel(4,g_ppline[k].y-th-1,g_line_canvas.TextWidth(pin),th,k,pin,g_ppline[k].ink,g_ppline[k].alpha,bold);
        }
     }
   for(int b=0;b<g_ppbox_n;b++)
     {
      if(!g_ppbox[b].zone)continue;
      int i=g_ppbox[b].occ,r=g_pocc[i].row;
      string t=FPPLabelText(g_pocc[i],g_pact.rows[r],3);
      if(StringLen(t)==0)continue;
      bool bold=FPPBold(g_pact.rows[r]);
      PPFont(bold);
      int tw=g_line_canvas.TextWidth(t);
      PPAddLabel(Lim((int)MathMax(g_ppbox[b].x0,0)+3,2,(int)MathMax(2,g_width-tw-2)),g_ppbox[b].y0-th-1,tw,th,-1-b,t,g_ppbox[b].ink,g_ppbox[b].alpha,bold);
     }
   if(g_pact.merge)
      for(int a=0;a<g_pplabel_n;a++)
        {
         if(g_pplabel[a].w==0 || g_pplabel[a].line<0)continue;
         for(int b=a+1;b<g_pplabel_n;b++)
           {
            if(g_pplabel[b].w==0 || g_pplabel[b].line<0 || MathAbs(g_pplabel[b].y-g_pplabel[a].y)>1)continue;
            int ea=g_pplabel[a].x+g_pplabel[a].w,eb=g_pplabel[b].x+g_pplabel[b].w;
            if(MathAbs(ea-eb)>3)continue;
            g_pplabel[a].text=g_pplabel[a].text+" / "+g_pplabel[b].text;
            PPFont(g_pplabel[a].bold);
            g_pplabel[a].w=g_line_canvas.TextWidth(g_pplabel[a].text);
            g_pplabel[a].x=Lim(ea-g_pplabel[a].w,2,(int)MathMax(2,g_width-g_pplabel[a].w-2));
            g_pplabel[b].w=0;   // merged away
           }
        }
   // Top to bottom: each label clears the labels placed above it.
   int ord[];
   ArrayResize(ord,g_pplabel_n);
   int n=0;
   for(int k=0;k<g_pplabel_n;k++)if(g_pplabel[k].w>0)ord[n++]=k;
   for(int a=1;a<n;a++){int v=ord[a],j=a;while(j>0 && g_pplabel[ord[j-1]].y>g_pplabel[v].y){ord[j]=ord[j-1];j--;}ord[j]=v;}
   for(int a=1;a<n;a++)
     {
      int k=ord[a];
      for(int pass=0;pass<n;pass++)
        {
         bool moved=false;
         for(int b=0;b<a;b++)
           {
            int o=ord[b];
            if(g_pplabel[k].x>g_pplabel[o].x+g_pplabel[o].w+2 || g_pplabel[o].x>g_pplabel[k].x+g_pplabel[k].w+2)continue;
            if(g_pplabel[k].y>=g_pplabel[o].y+g_pplabel[o].h || g_pplabel[o].y>=g_pplabel[k].y+g_pplabel[k].h)continue;
            g_pplabel[k].y=g_pplabel[o].y+g_pplabel[o].h;moved=true;
           }
         if(!moved)break;
        }
     }
  }
void PPDraw()
  {
   if(g_ppline_n==0 && g_ppbox_n==0 && g_ppoff_n==0)return;
   g_pp_font=-1;PPFont(false);
   for(int b=0;b<g_ppbox_n;b++)
     {
      bool sel=g_ppbox[b].occ==g_psel;
      if(g_ppbox[b].zone && g_pact.fill && !sel)continue;   // a shaded zone needs no outline
      int x0=g_ppbox[b].x0,x1=g_ppbox[b].x1,y0=g_ppbox[b].y0,y1=g_ppbox[b].y1;
      color ink=g_ppbox[b].ink;uchar a=g_ppbox[b].alpha;
      HLine(x0,x1,y0,ink,1,STYLE_SOLID,a);HLine(x0,x1,y1,ink,1,STYLE_SOLID,a);
      VLine(x0,y0,y1,ink,1,STYLE_SOLID,a);VLine(x1,y0,y1,ink,1,STYLE_SOLID,a);
     }
   for(int k=0;k<g_ppline_n;k++)
      HLine(g_ppline[k].x0,g_ppline[k].x1,g_ppline[k].y,g_ppline[k].ink,g_ppline[k].width,g_ppline[k].style,g_ppline[k].alpha);
   PPDrawGrip();
   PPLayoutLabels();
   for(int k=0;k<g_pplabel_n;k++)
      if(g_pplabel[k].w>0){PPFont(g_pplabel[k].bold);g_line_canvas.TextOut(g_pplabel[k].x,g_pplabel[k].y,g_pplabel[k].text,ColorToARGB(g_pplabel[k].ink,g_pplabel[k].alpha));}
   // Levels above or below the visible prices: nearest first, four at each edge.
   int th=g_line_canvas.TextHeight("Ag");
   for(int side=0;side<2;side++)
     {
      int shown=0;
      int used[];
      ArrayResize(used,g_ppoff_n);
      for(int k=0;k<g_ppoff_n;k++)used[k]=0;
      while(shown<4)
        {
         int best=-1,bd=0;
         for(int k=0;k<g_ppoff_n;k++)
           {
            if(used[k]!=0 || (side==0)!=(g_ppoff[k].y<0))continue;
            int d=side==0?-g_ppoff[k].y:g_ppoff[k].y-g_height;
            if(best<0 || d<bd){best=k;bd=d;}
           }
         if(best<0)break;
         used[best]=1;
         int i=g_ppoff[best].occ,r=g_pocc[i].row,q=g_ppoff[best].part;
         string t=Glyph(side==0?0x25B2:0x25BC)+" "+FPPPartName(g_pact.rows[r],q)+" "+DoubleToString(FPPLevel(g_pocc[i],q),_Digits);
         PPFont(FPPBold(g_pact.rows[r]));
         int tw=g_line_canvas.TextWidth(t);
         int y=side==0?4+shown*(th+2):g_height-4-(shown+1)*(th+2);
         g_line_canvas.TextOut((int)MathMax(2,g_width-tw-8),y,t,ColorToARGB(g_pact.rows[r].ink,230));
         shown++;
        }
     }
   g_line_canvas.FontSet("Segoe UI",U(15));g_pp_font=-1;
  }
// The price point under the pointer: a line (nearest within 3 px), else a zone or the edge of a range box.
bool FindPPAt(const int x,const int y,int &occ,int &part)
  {
   occ=-1;part=-1;
   int best=4;
   for(int k=g_ppline_n-1;k>=0;k--)
     {
      if(x<g_ppline[k].x0-2 || x>g_ppline[k].x1+2)continue;
      int d=(int)MathAbs(y-g_ppline[k].y);
      if(d<best){best=d;occ=g_ppline[k].occ;part=g_ppline[k].part;}
     }
   if(occ>=0)return true;
   for(int b=g_ppbox_n-1;b>=0;b--)
     {
      int x0=g_ppbox[b].x0,x1=g_ppbox[b].x1,y0=g_ppbox[b].y0,y1=g_ppbox[b].y1;
      if(x<x0-2 || x>x1+2 || y<y0-2 || y>y1+2)continue;
      bool edge=MathAbs(x-x0)<=3 || MathAbs(x-x1)<=3 || MathAbs(y-y0)<=3 || MathAbs(y-y1)<=3;
      if(g_ppbox[b].zone || edge){occ=g_ppbox[b].occ;part=3;return true;}
     }
   return false;
  }
string FPPTimeText(const datetime t)
  {
   long ny=FPServerToNY((long)t,g_zmode,g_zgmt);
   return g_dow_names[FPDow(FPFloorDiv(ny,86400))]+" "+FPHHMM((int)(FPFloorDiv(ny,60)%1440))+" New York";
  }
// Names of the other lines drawn at the same height (merged labels).
string PPAlsoAt(const int occ,const int part)
  {
   int y=FP_OFF;
   for(int k=0;k<g_ppline_n;k++)if(g_ppline[k].occ==occ && g_ppline[k].part==part){y=g_ppline[k].y;break;}
   if(y==FP_OFF)return "";
   string also="";
   for(int k=0;k<g_ppline_n;k++)
     {
      if((g_ppline[k].occ==occ && g_ppline[k].part==part) || MathAbs(g_ppline[k].y-y)>1)continue;
      int i=g_ppline[k].occ;
      string n=FPPPartName(g_pact.rows[g_pocc[i].row],g_ppline[k].part);
      if(StringFind(also,n)<0)also+=(StringLen(also)>0?", ":"")+n;
     }
   return also;
  }
void PPTip(const int i,const int part,string &lines[],color &accent)
  {
   int r=g_pocc[i].row,n=0,kind=g_pact.rows[r].kind;
   ArrayResize(lines,12);
   string head=FPPPartName(g_pact.rows[r],part);
   if(part==3 && FPPZoneKind(kind))head+=FPPArrow(g_pocc[i].dir);
   lines[n++]=Clip(head,44);
   string also=PPAlsoAt(i,part);
   if(StringLen(also)>0)lines[n++]="Also here\t"+Clip(also,40);
   string when=ZoneDateText(g_pocc[i].key*86400);
   if(kind==FPPK_PERIOD && g_pact.rows[r].sub==2)when=FPPWhen(g_pocc[i],g_pact.rows[r]);
   else if(FPPWeekly(g_pact.rows[r]))when="Week of "+when;
   lines[n++]=Clip(g_pact.rows[r].name,24)+"   "+when;
   if(part==3)
     {
      lines[n++]="Top\t"+DoubleToString(g_pocc[i].hi,_Digits);
      lines[n++]="Bottom\t"+DoubleToString(g_pocc[i].lo,_Digits);
      lines[n++]="CE\t"+DoubleToString((g_pocc[i].hi+g_pocc[i].lo)/2.0,_Digits);
      lines[n++]="Size\t"+DoubleToString((g_pocc[i].hi-g_pocc[i].lo)/_Point,0)+" pts";
     }
   else lines[n++]="Price\t"+DoubleToString(FPPLevel(g_pocc[i],part),_Digits);
   lines[n++]="Formed\t"+FPPTimeText(FPPAnchor(g_pocc[i],kind,part));
   string status="Not taken yet";
   if(g_pocc[i].live)status=kind==FPPK_PERIOD?"Forming (period still open)":"Forming (window still open)";
   else if(part==3 && kind==FPPK_WINDOW)status="";
   else if(part==3)status=g_pocc[i].tk[3]!=0?"Filled "+FPPTimeText(g_pocc[i].tk[3]):"Not filled yet";
   else if(g_pocc[i].tk[part]!=0)status="Taken "+FPPTimeText(g_pocc[i].tk[part]);
   if(StringLen(status)>0)lines[n++]="Status\t"+status;
   if(FPPRayBackAt(g_pocc[i],g_pact.rows[r],part))lines[n++]="Rayed back to the chart's first candle";
   if(FPPRayFwdAt(g_pocc[i],g_pact.rows[r],part))lines[n++]="Rayed forward to the right edge";
   else if(FPPEndAt(g_pocc[i],g_pact.rows[r],part)>0)lines[n++]="Extended by hand to "+FPPTimeText(FPPEndAt(g_pocc[i],g_pact.rows[r],part));
   lines[n++]=i==g_psel?"Selected: ray it, hide it, or drag its right end":"Click to select it (ray, hide, extend)";
   ArrayResize(lines,n);accent=g_pact.rows[r].ink;
  }
// ---- selection: a click on a price point selects that line (a gap, FVG or OB: the zone).
// Its buttons ray it back to the chart's first candle or forward to the right edge, hide it
// on this chart, reset an end set by hand, or open its row; its right end can be dragged.
bool PPSelValid(){return g_psel_uid!=0 && g_psel>=0 && g_psel<g_pocc_n && g_pocc[g_psel].uid==g_psel_uid && g_pocc[g_psel].key==g_psel_key;}
bool PPPress(const int x,const int y)
  {
   int occ=-1,part=-1;
   if(!g_pact.enabled || !FindPPAt(x,y,occ,part))return false;
   g_psel_uid=g_pocc[occ].uid;g_psel_key=g_pocc[occ].key;g_psel_part=part;g_psel=occ;
   g_psel_x=x;g_psel_y=y;
   g_dirty=true;g_ui_dirty=true;
   return true;
  }
void PPClearSel()
  {
   if(g_psel_uid==0)return;
   g_psel_uid=0;g_psel_key=0;g_psel=-1;g_psel_part=-1;g_dirty=true;g_ui_dirty=true;
  }
// The line (or zone) the buttons and the end drag act on.
int PPSelTarget()
  {
   if(!PPSelValid())return -1;
   int r=g_pocc[g_psel].row;
   if(r<0 || r>=g_pact.count)return -1;
   return FPPTarget(g_pact.rows[r].kind,g_psel_part);
  }
void BuildPointChip()
  {
   int t=PPSelTarget();
   if(t<0)return;
   int r=g_pocc[g_psel].row;
   bool back=FPPRayBackAt(g_pocc[g_psel],g_pact.rows[r],t),fwd=FPPRayFwdAt(g_pocc[g_psel],g_pact.rows[r],t);
   bool hand=g_pocc[g_psel].pend[t]>0;
   int w=hand?270:206;
   int x=Lim(g_psel_x+U(10),0,(int)MathMax(0,g_width-U(w))),y=Lim(g_psel_y+U(12),0,(int)MathMax(0,g_height-U(24)));
   g_pchip_x=x;g_pchip_y=y;g_pchip_w=w;
   Button("X.RayB",Glyph(0x25C0)+" Ray",x,y,52,22,back?clrLightSteelBlue:clrWhite);
   Button("X.RayF","Ray "+Glyph(0x25B6),x+U(54),y,52,22,fwd?clrLightSteelBlue:clrWhite);
   Button("X.Hide","Hide",x+U(108),y,44);
   Button("X.Row","Row...",x+U(154),y,50);
   if(hand)Button("X.Reset","Reset end",x+U(206),y,64);
   Tooltip("X.RayB","Ray it back to the chart's first candle (this chart only). Click again to undo.");
   Tooltip("X.RayF","Ray it forward to the right edge, taken or not (this chart only). Click again to undo. Or drag its right end.");
   Tooltip("X.Hide","Hide it on this chart. Its row's ... button can show it again.");
   Tooltip("X.Row","Open its row in the Price points window");
   if(hand)Tooltip("X.Reset","Undo the end you dragged it to");
  }
bool HitPointChip(const int x,const int y)
  {return !g_hidden && PPSelValid() && x>=g_pchip_x && x<=g_pchip_x+U(g_pchip_w) && y>=g_pchip_y && y<=g_pchip_y+U(22);}
void PPChipClick(const string key)
  {
   int t=PPSelTarget();
   if(t<0)return;
   int i=g_psel,r=g_pocc[i].row,f=g_pocc[i].pflags[t];
   datetime e=g_pocc[i].pend[t];
   uint uid=g_pocc[i].uid;
   long k=g_pocc[i].key;
   if(key=="RayB")
     {
      bool want=!FPPRayBackAt(g_pocc[i],g_pact.rows[r],t);
      f&=~3;
      if(want!=FPPRay(g_pocc[i],g_pact.rows[r]))f|=want?1:2;
      if(PPSetFlags(uid,k,t,f,e))Status(want?"Rayed back to the chart's first candle (this chart).":"Ray back removed.");
      g_ui_dirty=true;
     }
   else if(key=="RayF")
     {
      bool want=!FPPRayFwdAt(g_pocc[i],g_pact.rows[r],t);
      if(want){f|=8;e=0;}else f&=~8;
      if(PPSetFlags(uid,k,t,f,e))Status(want?"Rayed forward to the right edge (this chart).":"Ray forward removed.");
      g_ui_dirty=true;
     }
   else if(key=="Reset")
     {
      if(PPSetFlags(uid,k,t,f,0))Status("End reset: it ends as its row is set again.");
      g_ui_dirty=true;
     }
   else if(key=="Hide")
     {
      if(PPSetFlags(uid,k,t,f|4,e))Status("Hidden on this chart. Its row's ... button in Price points shows it again.");
      PPClearSel();
     }
   else if(key=="Row")OpenPointsAt(r);
  }
// ---- drag the selected price point's right end (this chart only)
// The selected line's (zone's) right end on screen: false when it isn't drawn.
bool PPSelEnd(int &x,int &y0,int &y1)
  {
   int t=PPSelTarget();
   if(t<0)return false;
   int kind=g_pact.rows[g_pocc[g_psel].row].kind;
   if(t==3)
      for(int b=0;b<g_ppbox_n;b++)
         if(g_ppbox[b].occ==g_psel){x=g_ppbox[b].x1;y0=g_ppbox[b].y0;y1=g_ppbox[b].y1;return true;}
   for(int k=0;k<g_ppline_n;k++)
      if(g_ppline[k].occ==g_psel && FPPTarget(kind,g_ppline[k].part)==t){x=g_ppline[k].x1;y0=g_ppline[k].y;y1=g_ppline[k].y;return true;}
   return false;
  }
// A press on the grip at the selected price point's right end starts dragging it.
bool PPDragBegin(const int x,const int y)
  {
   if(g_hidden || g_popup!=0)return false;
   int ex=0,y0=0,y1=0;
   if(!PPSelEnd(ex,y0,y1) || ex<0 || ex>=g_width || MathAbs(x-ex)>U(6) || y<y0-U(6) || y>y1+U(6))return false;
   int t=PPSelTarget();
   g_ppdrag=true;g_ppdrag_part=t;g_ppdrag_px=x;g_ppdrag_moved=false;
   g_ppdrag_flags=g_pocc[g_psel].pflags[t];g_ppdrag_end=g_pocc[g_psel].pend[t];
   HoldScroll();
   return true;
  }
// The end follows the pointer (never before the candle the level starts from); a plain
// click changes nothing. A dragged end replaces ray forward.
void PPDragMove(const int x,const int y)
  {
   if(!g_ppdrag || !PPSelValid())return;
   if(!g_ppdrag_moved){if(MathAbs(x-g_ppdrag_px)<3)return;g_ppdrag_moved=true;}
   datetime t=0;double p=0;
   if(!Point(x,y,t,p))return;
   int kind=g_pact.rows[g_pocc[g_psel].row].kind;
   datetime least=FPPAnchor(g_pocc[g_psel],kind,g_ppdrag_part)+60;
   if(t<least)t=least;
   g_pocc[g_psel].pend[g_ppdrag_part]=t;
   g_pocc[g_psel].pflags[g_ppdrag_part]=g_ppdrag_flags&~8;
   g_dirty=true;
  }
void PPDragEnd()
  {
   if(!g_ppdrag)return;
   g_ppdrag=false;ReleaseScroll();
   if(!g_ppdrag_moved || !PPSelValid())return;
   int t=g_ppdrag_part;
   if(PPSetFlags(g_pocc[g_psel].uid,g_pocc[g_psel].key,t,g_pocc[g_psel].pflags[t],g_pocc[g_psel].pend[t]))
      Status("Extended to "+FPPTimeText(g_pocc[g_psel].pend[t])+" (this chart). Reset end undoes it.");
   g_ui_dirty=true;
  }
void PPDragCancel()
  {
   if(!g_ppdrag)return;
   if(PPSelValid()){g_pocc[g_psel].pflags[g_ppdrag_part]=g_ppdrag_flags;g_pocc[g_psel].pend[g_ppdrag_part]=g_ppdrag_end;}
   g_ppdrag=false;ReleaseScroll();g_dirty=true;
  }
// The grip at the selected price point's right end.
void PPDrawGrip()
  {
   int x=0,y0=0,y1=0;
   if(!PPSelEnd(x,y0,y1) || x<0 || x>=g_width)return;
   int y=(y0+y1)/2,h=U(4);
   color ink=g_pact.rows[g_pocc[g_psel].row].ink;
   g_line_canvas.FillRectangle(x-h,y-h,x+h,y+h,ColorToARGB(ink,255));
   g_line_canvas.Rectangle(x-h,y-h,x+h,y+h,ColorToARGB(g_chart_fg,255));
  }

// ---- Price points window: Parameters, Visualization, Fill and Price points tabs
void PPPreview(const bool rebuild)
  {
   g_pact=g_peditor?g_pedit:g_pcfg;
   if(rebuild)g_pocc_dirty=true;
   g_dirty=true;
  }
void OpenPoints()
  {
   if(g_editor){Status("Finish or cancel Properties first.");return;}
   if(g_zeditor){Status("Close the Zones window first.");return;}
   if(g_reditor){Status("Close the Risk window first.");return;}
   if(g_drag!=0 || g_armed)CancelDrag();
   ClosePopup();g_list=false;g_pedit=g_pcfg;g_peditor=true;g_ppage=0;
   PPPreview(false);g_ui_dirty=true;
  }
// The window on the page of the Price points tab that holds the row.
void OpenPointsAt(const int row)
  {
   if(!g_peditor)OpenPoints();
   if(!g_peditor || row<0 || row>=g_pedit.count)return;
   g_ptab=3;g_pfilter=-1;
   g_ppage=row/(int)MathMax(1,g_rows-1);
   g_ui_dirty=true;
   Status("Row "+IntegerToString(row+1)+": "+g_pedit.rows[row].name+".");
  }
// Table controls are named by the row's identity, so a click that arrives before the table
// is rebuilt (after a sort, say) still reaches its row.
int PPRowOf(const string digits)
  {
   if(StringLen(digits)==0)return -1;
   uint uid=(uint)StringToInteger(digits);
   for(int i=0;i<g_pedit.count;i++)if(g_pedit.rows[i].uid==uid)return i;
   return -1;
  }
string PPKey(const int row){return IntegerToString((long)g_pedit.rows[row].uid);}
void ClosePoints(){ClosePopup();g_peditor=false;g_slider_drag=false;PPPreview(true);g_ui_dirty=true;}
void PEndEdit(const string name)
  {
   if(!g_peditor || StringFind(name,UIS("N."))!=0 || RegType(name)!=OBJ_EDIT)return;
   string key=StringSubstr(name,StringLen(UIS("N."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   bool accepted=true,rebuild=false;
   if(StringFind(key,"Name")==0)
     {
      int i=PPRowOf(StringSubstr(key,4));
      if(i>=0){string t=text;StringTrimLeft(t);StringTrimRight(t);g_pedit.rows[i].name=StringLen(t)>0?StringSubstr(t,0,40):"Price point";}
     }
   else if(StringFind(key,"Start")==0 || StringFind(key,"End")==0)
     {
      bool start=StringFind(key,"Start")==0;
      int i=PPRowOf(StringSubstr(key,start?5:3)),m=0;
      if(i<0)return;   // a row removed since the table was drawn
      if(FPParseHHMM(text,m))
        {
         int kind=g_pedit.rows[i].kind;
         if(start)
           {
            if(kind==FPPK_WINDOW && m==g_pedit.rows[i].end)accepted=false;
            else g_pedit.rows[i].start=m;
           }
         else if(kind==FPPK_FVG || kind==FPPK_OB)
           {
            int len=(m-g_pedit.rows[i].start+1440)%1440;
            if(len<1 || len>240)accepted=false;else g_pedit.rows[i].len=len;
           }
         else if(kind==FPPK_WINDOW && m==g_pedit.rows[i].start)accepted=false;
         else g_pedit.rows[i].end=m;
         rebuild=accepted;
        }
      else accepted=false;
     }
   else if(key=="Days"){if(Numeric(text)){g_pedit.days_back=Lim((int)StringToInteger(text),1,120);rebuild=true;}else accepted=false;}
   else if(key=="Weeks"){if(Numeric(text)){g_pedit.weeks_back=Lim((int)StringToInteger(text),1,26);rebuild=true;}else accepted=false;}
   else if(key=="Months"){if(Numeric(text)){g_pedit.months_back=Lim((int)StringToInteger(text),1,12);rebuild=true;}else accepted=false;}
   else if(key=="Opacity"){if(Numeric(text)){g_pedit.opacity=Lim((int)StringToInteger(text),0,100);PlaceOpacityThumb();}else accepted=false;}
   else return;
   if(!accepted){g_edit_error=true;Status("Invalid value; previous setting restored.");g_ui_dirty=true;}
   PPPreview(rebuild);
  }
bool HarvestPointEdits()
  {
   if(!g_peditor)return true;
   g_edit_error=false;
   string prefix=UIS("N.");
   for(int i=0;i<g_reg_count;i++)
      if(g_reg[i].type==OBJ_EDIT && StringFind(g_reg[i].name,prefix)==0)PEndEdit(g_reg[i].name);
   PPPopupHarvest();
   return !g_edit_error;
  }
bool ApplyPoints(const bool close)
  {
   if(!g_peditor)return false;
   if(!HarvestPointEdits())return false;
   FPPointConfig previous=g_pcfg;g_pcfg=g_pedit;
   if(!SavePoints()){g_pcfg=previous;Status("Could not save price point settings. Check the Experts log.");return false;}
   Status("Price point settings saved for every chart using workspace \""+InpWorkspace+"\".");
   if(close)ClosePoints();else {ClosePopup();PPPreview(true);g_ui_dirty=true;}
   return true;
  }
void TogglePointsShown()
  {
   g_pcfg.enabled=!g_pcfg.enabled;
   if(g_peditor)g_pedit.enabled=g_pcfg.enabled;
   SavePoints();PPPreview(true);
   if(!g_pcfg.enabled)PPClearSel();
   g_ui_dirty=true;
   Status(g_pcfg.enabled?"Price points shown.":"Price points hidden ("+InpPointsHotkey+" shows them).");
  }
void UpdatePointsButton()
  {
   if(g_hidden || !g_owner)return;
   Button("T.Points","Points",g_toolbar_x+U(FP_TOOLBAR_WIDTH-220),g_toolbar_y+U(1),60,18,g_peditor?clrLightSteelBlue:(g_pcfg.enabled?clrWhite:clrGainsboro));
   Tooltip("T.Points","Price points: session highs and lows, gaps, opening ranges, FPFVG/FPOB and OHLC ("+InpPointsHotkey+" shows or hides them)");
  }
bool HitPointsButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-220) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-160) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
int PointsFiltered(int &idx[])
  {
   ArrayResize(idx,g_pedit.count);int n=0;
   for(int i=0;i<g_pedit.count;i++)if(g_pfilter<0 || g_pedit.rows[i].group==g_pfilter)idx[n++]=i;
   return n;
  }
string PStyleText(const int s){if(s<0)return "Role";string n[]={"Solid","Dash","Dot","D-dot","D-d-d"};return n[Lim(s,0,4)];}
string PLabelText(const int l){string n[]={"Auto","Name","+day","+price","Off"};return n[Lim(l,0,4)];}
string PEndsText(const int e){string n[]={"Auto","Take","Run on","Day","Week"};return n[Lim(e,0,4)];}
void PPB(string &labels[],int &bits[],int &widths[],int &n,const string label,const int bit,const int width)
  {labels[n]=label;bits[n]=bit;widths[n]=width;n++;}
// The part switches of a row's kind (FVG/OB edges switch together).
int PPartButtons(const int kind,string &labels[],int &bits[],int &widths[])
  {
   ArrayResize(labels,7);ArrayResize(bits,7);ArrayResize(widths,7);
   int n=0;
   if(kind==FPPK_OPEN){PPB(labels,bits,widths,n,"O",FPPP_O,18);return n;}
   if(kind==FPPK_PERIOD)
     {PPB(labels,bits,widths,n,"O",FPPP_O,18);PPB(labels,bits,widths,n,"H",FPPP_H,18);PPB(labels,bits,widths,n,"L",FPPP_L,18);PPB(labels,bits,widths,n,"C",FPPP_C,18);PPB(labels,bits,widths,n,"CE",FPPP_CE,24);}
   else if(kind==FPPK_GAP)
     {PPB(labels,bits,widths,n,"O",FPPP_O,18);PPB(labels,bits,widths,n,"C",FPPP_C,18);PPB(labels,bits,widths,n,"CE",FPPP_CE,24);PPB(labels,bits,widths,n,"Box",FPPP_BOX,30);}
   else if(kind==FPPK_FVG || kind==FPPK_OB)
     {PPB(labels,bits,widths,n,"Edges",FPPP_H|FPPP_L,42);PPB(labels,bits,widths,n,"CE",FPPP_CE,24);PPB(labels,bits,widths,n,"Box",FPPP_BOX,30);}
   else
     {PPB(labels,bits,widths,n,"H",FPPP_H,18);PPB(labels,bits,widths,n,"L",FPPP_L,18);PPB(labels,bits,widths,n,"CE",FPPP_CE,24);PPB(labels,bits,widths,n,"Box",FPPP_BOX,30);}
   PPB(labels,bits,widths,n,"1/4",FPPP_Q,24);   // quadrants: 25% and 75%
   PPB(labels,bits,widths,n,"1/8",FPPP_E,24);   // octants: 12.5%, 37.5%, 62.5%, 87.5%
   return n;
  }
void PointsParamsTab(const int x,int cy)
  {
   Check("N.Master","Show price points ("+InpPointsHotkey+")",g_pedit.enabled,x+U(12),cy,300);cy+=U(28);
   Label("N.GrpL","Groups",x+U(12),cy+U(4));
   int gx[]={96,232,368};
   for(int g=0;g<FPP_GROUPS;g++)Check("N.Grp"+IntegerToString(g),FPPGroupName(g),g_pedit.group_on[g],x+U(gx[g%3]),cy+U((g/3)*26),130);
   cy+=U(56);
   Label("N.BackL","Look back",x+U(12),cy+U(4));
   Edit("N.Days",IntegerToString(g_pedit.days_back),x+U(96),cy,40);Label("N.DaysL","days",x+U(140),cy+U(4));
   Edit("N.Weeks",IntegerToString(g_pedit.weeks_back),x+U(184),cy,40);Label("N.WeeksL","weeks",x+U(228),cy+U(4));
   Edit("N.Months",IntegerToString(g_pedit.months_back),x+U(282),cy,40);Label("N.MonthsL","months",x+U(326),cy+U(4));
   Tooltip("N.Days","Trading days, Monday to Friday, today included (1..120): sessions, ranges, gaps, FPFVG/FPOB and daily levels. Older than the terminal's M1 history: read from M5 (FPFVG/FPOB need M1).");
   Tooltip("N.Weeks","Weeks, this one included (1..26): NWOG and weekly levels");
   Tooltip("N.Months","Months, this one included (1..12): monthly levels");
   cy+=U(28);
   Check("N.EndTaken","Lines end where price takes them",g_pedit.end_taken,x+U(12),cy,250);
   Label("N.TakenL","Taken levels",x+U(276),cy+U(4));
   string tk[]={"Dim","Hide","Keep"};int bx=x+U(360);
   for(int k=0;k<3;k++){Button("N.Taken"+IntegerToString(k),tk[k],bx,cy,52,22,g_pedit.taken_show==k?clrLightSteelBlue:clrWhite);bx+=U(54);}
   Tooltip("N.EndTaken","A high ends at the first candle trading above it, a low below it; opens, closes and CEs when price comes back to them; a zone when it is filled. Off: every line runs to the right edge.");
   Tooltip("N.Taken0","Taken levels end where they were taken, drawn faint");
   Tooltip("N.Taken1","Taken levels disappear");
   Tooltip("N.Taken2","Taken levels end where they were taken, drawn as set");
   cy+=U(28);
   Label("N.TakenEndL","Taken lines run to",x+U(12),cy+U(4));
   string te[]={"The take","End of that day","End of that week"};int tew[]={80,120,128};bx=x+U(140);
   for(int k=0;k<3;k++){Button("N.TakenEnd"+IntegerToString(k),te[k],bx,cy,tew[k],22,g_pedit.taken_end==k?clrLightSteelBlue:clrWhite);bx+=U(tew[k]+2);}
   Tooltip("N.TakenEnd0","A taken line or zone ends at the candle that took it");
   Tooltip("N.TakenEnd1","A taken line or zone runs on to the end of the trading day it was taken in (17:00 New York)");
   Tooltip("N.TakenEnd2","A taken line or zone runs on to the end of the week it was taken in (Friday 17:00 New York)");
   cy+=U(28);
   Label("N.WeekL","Week opens with",x+U(12),cy+U(4));
   Button("N.Week0","First candle after the weekend",x+U(120),cy,206,22,g_pedit.week_open==0?clrLightSteelBlue:clrWhite);
   Button("N.Week1","Monday's first candle",x+U(328),cy,150,22,g_pedit.week_open==1?clrLightSteelBlue:clrWhite);
   Tooltip("N.Week0","The Sunday candle when your broker has one, otherwise Monday's first. Used by NWOG and the weekly open.");
   Tooltip("N.Week1","Always Monday's first candle (server time), skipping a Sunday candle. Used by NWOG and the weekly open.");
   cy+=U(28);
   datetime now=ZoneNow();long ny=FPServerToNY((long)now,g_zmode,g_zgmt);
   string sign=g_zgmt>=0?"+":"",dst=g_zmode==3?" with EU DST":(g_zmode==4?" with US DST":"");
   string model=g_zmode==1?"NY + 7 h":"GMT"+sign+IntegerToString(g_zgmt)+dst;
   Label("N.BrokerL","Broker time",x+U(12),cy+U(4));
   Label("N.Clock","New York "+FPHHMM((int)(FPFloorDiv(ny,60)%1440))+" = server "+TimeToString(now,TIME_MINUTES)+"   ("+model+", set in the Zones window)",x+U(96),cy+U(4),clrDimGray);
   cy+=U(28);
   Label("N.AlertL","Alerts",x+U(12),cy+U(4));
   Check("N.Sound","Sound",g_pedit.alert_sound,x+U(96),cy,76);
   Check("N.Push","Push to phone",g_pedit.alert_push,x+U(176),cy,124);
   Button("N.Test","Test",x+U(306),cy,56);
   Label("N.AlertHint","Switch them on per row: ... > Alert",x+U(370),cy+U(4),clrDimGray);
   Tooltip("N.Push","Needs your MetaQuotes ID in Tools > Options > Notifications.");
  }
void PointsVisualTab(const int x,const int cy)
  {
   Label("N.TfTitle","Show each group up to",x+U(12),cy);
   int ry=cy+U(24);
   for(int g=0;g<FPP_GROUPS;g++)
     {
      string n=IntegerToString(g);
      Label("N.TfG"+n,FPPGroupName(g),x+U(12),ry+U(4));
      Button("N.TfDn"+n,"<",x+U(130),ry,24);
      Label("N.TfV"+n,g_tf_names[Lim(g_pedit.group_tf[g],0,20)],x+U(162),ry+U(4));
      Button("N.TfUp"+n,">",x+U(200),ry,24);
      ry+=U(26);
     }
   int rx=x+U(270),qy=cy;
   Label("N.LblL","Labels",rx,qy+U(4));
   string lm[]={"Name","+ day","+ price","Off"};int lw[]={52,50,58,40};int bx=rx+U(80);
   for(int k=0;k<4;k++){Button("N.Lbl"+IntegerToString(k),lm[k],bx,qy,lw[k],22,g_pedit.label_mode==k?clrLightSteelBlue:clrWhite);bx+=U(lw[k]+2);}
   Tooltip("N.Lbl1","Name and day, e.g. ASH Tue 17");
   Tooltip("N.Lbl2","Name and price");
   qy+=U(28);
   Label("N.FsL","Label size",rx,qy+U(4));Button("N.FsDn","-",rx+U(80),qy,24);
   Label("N.FsV",IntegerToString(g_pedit.label_size)+" px",rx+U(110),qy+U(4));Button("N.FsUp","+",rx+U(156),qy,24);
   qy+=U(28);
   Check("N.Bold","Bold labels",g_pedit.label_bold,rx,qy,300);qy+=U(27);
   Tooltip("N.Bold","Every row's labels in bold; a row's ... options can set its own");
   Check("N.Merge","Merge labels at the same price",g_pedit.merge,rx,qy,300);qy+=U(27);
   Check("N.Pin","Pin names at the left edge",g_pedit.pin_left,rx,qy,300);qy+=U(27);
   Check("N.Off","Arrows for levels off screen",g_pedit.offscreen,rx,qy,300);qy+=U(27);
   Check("N.Hover","Hover info for price points",g_pedit.hover,rx,qy,300);
   Tooltip("N.Pin","A level that starts left of the chart shows its name at the left edge too");
   Tooltip("N.Off","Untaken levels above or below the visible prices: an arrow with name and price at the top or bottom edge");
  }
void PointsFillTab(const int x,int cy)
  {
   Check("N.Fill","Fill zones (gaps, FVGs, order blocks)",g_pedit.fill,x+U(12),cy,300);cy+=U(30);
   Label("N.OpacityLabel","Opacity %",x+U(12),cy+U(4));Edit("N.Opacity",IntegerToString(g_pedit.opacity),x+U(84),cy,48);
   g_slider_x0=x+U(148);g_slider_x1=x+U(FPP_PANEL_WIDTH-22);g_slider_y0=cy-U(2);g_slider_y1=cy+U(24);g_slider_on=true;
   Box("N.OpTrack",g_slider_x0,cy+U(9),FPP_PANEL_WIDTH-170,5,clrSilver);
   PlaceOpacityThumb();
   cy+=U(36);
   Label("N.TintL","Zone shades",x+U(12),cy+U(4));
   Button("N.Tint0","OB lighter, FVG darker",x+U(120),cy,170,22,g_pedit.tint==0?clrLightSteelBlue:clrWhite);
   Button("N.Tint1","One shade",x+U(292),cy,90,22,g_pedit.tint==1?clrLightSteelBlue:clrWhite);
   cy+=U(30);
   Check("N.Range","Shade the range of rows that draw their box",g_pedit.range_fill,x+U(12),cy,340);cy+=U(32);
   Label("N.FillNote","A row's Box part (Price points tab) draws its zone, or its window's range.",x+U(12),cy,clrDimGray);
  }
void PointsTableTab(const int x,const int y,int cy)
  {
   string chips[]={"All","Gaps","Pre-sessions","Opening ranges","FPFVG & FPOB","Sessions","OHLC"};int cw[]={36,46,86,104,98,66,48};int cx=x+U(12);
   for(int f=0;f<7;f++){Button("N.Flt"+IntegerToString(f),chips[f],cx,cy,cw[f],22,g_pfilter==f-1?clrLightSteelBlue:clrWhite);cx+=U(cw[f]+2);}
   cy+=U(26);
   string up=Glyph(0x25B2),dn=Glyph(0x25BC);
   string arrow=g_psort_desc?dn:up,nh="Name",th="Start / End";
   if(g_psort==1)nh+=" "+arrow;
   if(g_psort==2)th+=" "+arrow;
   Label("N.Head0","On",x+U(12),cy);
   Button("N.SortName",nh,x+U(40),cy-U(2),100,18,clrGainsboro);
   Button("N.SortTime",th,x+U(142),cy-U(2),90,18,clrGainsboro);
   int hx[]={234,394,452,482,512,568};
   string heads[]={"Parts","Style","W","Col","Label","Ends"};
   for(int c=0;c<6;c++)Label("N.Head"+IntegerToString(c+1),heads[c],x+U(hx[c]),cy);
   Tooltip("N.SortName","Sort by name (click again to reverse)");
   Tooltip("N.SortTime","Sort by time of day, evening rows first (click again to reverse). New York time, HH:MM.");
   Tooltip("N.Head1","Lines and zones each row draws: O open, H high, L low, C close, CE 50%, Box its zone or range, 1/4 quadrants (25%, 75%), 1/8 octants (12.5% to 87.5%)");
   Tooltip("N.Head6","Auto: as set in Parameters. Take: ends where price takes it. Day, Week: runs to the end of the day or week it was taken in. Run on: to the right edge.");
   cy+=U(21);
   int idx[];int n=PointsFiltered(idx);
   int rows=(int)MathMax(1,g_rows-1),pages=(int)MathMax(1,(n+rows-1)/rows);
   g_ppage=Lim(g_ppage,0,pages-1);
   for(int r=0;r<rows;r++)
     {
      int k=g_ppage*rows+r;
      if(k>=n)break;
      int i=idx[k],ry=cy+U(r*24),kind=g_pedit.rows[i].kind;string s=PPKey(i);
      Button("N.On"+s,g_pedit.rows[i].enabled?"x":"",x+U(12),ry,26);
      Edit("N.Name"+s,g_pedit.rows[i].name,x+U(40),ry,100);
      if(StringLen(g_pedit.rows[i].sname)>0)Tooltip("N.Name"+s,"On the chart: "+g_pedit.rows[i].sname+" (set under ...)");
      Tooltip("N.On"+s,FPPKindText(g_pedit.rows[i]));
      if(kind==FPPK_PERIOD)
        {
         string per=g_pedit.rows[i].sub==0?"Daily":(g_pedit.rows[i].sub==1?"Weekly":"Monthly");
         Label("N.StartL"+s,per,x+U(146),ry+U(4),clrDimGray);
        }
      else
        {
         Edit("N.Start"+s,FPHHMM(g_pedit.rows[i].start),x+U(142),ry,44);
         if(kind==FPPK_GAP && g_pedit.rows[i].sub==2){Label("N.EndL"+s,"wk open",x+U(190),ry+U(4),clrDimGray);Tooltip("N.Start"+s,"Friday's close candle");}
         else if(kind==FPPK_OPEN)Label("N.EndL"+s,"-",x+U(204),ry+U(4),clrDimGray);
         else if(kind==FPPK_FVG || kind==FPPK_OB)Edit("N.End"+s,FPHHMM(g_pedit.rows[i].start+g_pedit.rows[i].len),x+U(188),ry,44);
         else Edit("N.End"+s,FPHHMM(g_pedit.rows[i].end),x+U(188),ry,44);
         if(kind==FPPK_GAP && g_pedit.rows[i].sub<2){Tooltip("N.Start"+s,"Close candle of the session before");Tooltip("N.End"+s,"Open: the first candle from this time");}
        }
      string pl[];
      int pb[];
      int pw[];
      int pn=PPartButtons(kind,pl,pb,pw),px=x+U(234);
      for(int b=0;b<pn;b++)
        {
         bool on=(g_pedit.rows[i].parts&pb[b])==pb[b];
         Button("N.P"+IntegerToString(pb[b])+"_"+s,pl[b],px,ry,pw[b],22,on?clrLightSteelBlue:clrWhite);
         px+=U(pw[b]+2);
        }
      Button("N.Style"+s,PStyleText(g_pedit.rows[i].style)+" v",x+U(394),ry,56);
      Button("N.Width"+s,IntegerToString(g_pedit.rows[i].width)+" v",x+U(452),ry,28);
      Button("N.Color"+s,"",x+U(482),ry,28,22,g_pedit.rows[i].ink);
      Button("N.Label"+s,PLabelText(g_pedit.rows[i].label)+" v",x+U(512),ry,54);
      Button("N.Ends"+s,PEndsText(g_pedit.rows[i].ends)+" v",x+U(568),ry,58);
      Button("N.More"+s,"...",x+U(628),ry,24);
      Tooltip("N.More"+s,"Group, type, name on the chart, line names, days drawn, ray back, alert, bold labels, hidden ones");
      Button("N.Remove"+s,Glyph(0xD7),x+U(654),ry,22);
     }
   if(n==0)Label("N.Empty","No price points in this group. Click Add.",x+U(16),cy+U(4),clrDimGray);
   int fy=y+PanelHeight()-U(93);
   Button("N.Add","Add",x+U(12),fy,52);Button("N.Defaults","Defaults",x+U(66),fy,70);Button("N.Sort","Sort by time",x+U(138),fy,92);
   Tooltip("N.Defaults","Restore the default list: all 55 ICT price points in 30 rows (sessions and NDOG switched on)");
   Button("N.PageBack","<",x+U(270),fy,26);Button("N.PageNext",">",x+U(298),fy,26);
   Label("N.Page",IntegerToString(g_ppage+1)+" / "+IntegerToString(pages),x+U(332),fy+U(4));
  }
void BuildPointsPanel()
  {
   int x=g_panel_x,y=g_panel_y,W=FPP_PANEL_WIDTH;
   Box("N.Background",x,y,W,184+g_rows*24,clrWhiteSmoke);
   Label("N.Title","Price points",x+U(10),y+U(7));
   Label("N.Shared","Shared by all charts of workspace \""+Clip(InpWorkspace,16)+"\"",x+U(250),y+U(7),clrDimGray);
   string tabs[]={"Parameters","Visualization","Fill","Price points"};int widths[]={92,104,52,96};int tx=x+U(10);
   for(int t=0;t<4;t++){Button("N.Tab"+IntegerToString(t),tabs[t],tx,y+U(30),widths[t],23,t==g_ptab?clrWhite:clrGainsboro);tx+=U(widths[t]+2);}
   int cy=y+U(64);
   if(g_ptab==0)PointsParamsTab(x,cy);
   else if(g_ptab==1)PointsVisualTab(x,cy);
   else if(g_ptab==2)PointsFillTab(x,cy);
   else PointsTableTab(x,y,cy);
   int by=y+PanelHeight()-U(31);
   Button("N.Save","Save",x+U(W-172),by-U(30),72);Button("N.Load","Load",x+U(W-98),by-U(30),72);
   Tooltip("N.Save","Save these settings as a named preset");
   Tooltip("N.Load","Load or delete a preset (ICT price points and All off are built in)");
   Button("N.OK","OK",x+U(W-246),by,72);Button("N.Cancel","Cancel",x+U(W-172),by,72);Button("N.Apply","Apply",x+U(W-98),by,72);
   // A row's options stay open while the table behind them is rebuilt.
   if(g_ppopup_reopen>=0){int r=g_ppopup_reopen;g_ppopup_reopen=-1;PointMorePopup(r);}
  }
void PointsClick(const string key)
  {
   if(key!="Cancel")
     {
      // Read active edits before their focus-loss events or an Apply click race.
      if(!HarvestPointEdits())return;
      if(g_ui_dirty){ClosePopup();BuildUI();}
     }
   if(key=="OK"){ApplyPoints(true);return;}
   if(key=="Apply"){ApplyPoints(false);return;}
   if(key=="Cancel"){ClosePoints();return;}
   if(key=="Save"){PresetBrowser(true);return;}
   if(key=="Load"){PresetBrowser(false);return;}
   if(StringFind(key,"Tab")==0){ClosePopup();g_ptab=Lim((int)StringToInteger(StringSubstr(key,3)),0,3);g_ui_dirty=true;return;}
   if(key=="Test"){PPFireAlert("",0,true);return;}
   if(StringFind(key,"Style")==0){Dropdown(20,PPRowOf(StringSubstr(key,5)));return;}
   if(StringFind(key,"Width")==0){Dropdown(21,PPRowOf(StringSubstr(key,5)));return;}
   if(StringFind(key,"Label")==0){Dropdown(22,PPRowOf(StringSubstr(key,5)));return;}
   if(StringFind(key,"Ends")==0){Dropdown(23,PPRowOf(StringSubstr(key,4)));return;}
   if(StringFind(key,"Color")==0){int i=PPRowOf(StringSubstr(key,5));if(i>=0)Palette(-2000-i);return;}
   if(StringFind(key,"More")==0){PointMorePopup(PPRowOf(StringSubstr(key,4)));return;}
   bool rebuild=false;
   if(key=="Master"){g_pedit.enabled=!g_pedit.enabled;rebuild=true;}
   else if(StringFind(key,"Grp")==0){int g=Lim((int)StringToInteger(StringSubstr(key,3)),0,FPP_GROUPS-1);g_pedit.group_on[g]=!g_pedit.group_on[g];rebuild=true;}
   else if(key=="EndTaken")g_pedit.end_taken=!g_pedit.end_taken;
   else if(StringFind(key,"TakenEnd")==0)g_pedit.taken_end=Lim((int)StringToInteger(StringSubstr(key,8)),0,2);
   else if(StringFind(key,"Taken")==0)g_pedit.taken_show=Lim((int)StringToInteger(StringSubstr(key,5)),0,2);
   else if(StringFind(key,"Week")==0 && StringLen(key)==5){g_pedit.week_open=Lim((int)StringToInteger(StringSubstr(key,4)),0,1);rebuild=true;}
   else if(key=="Sound")g_pedit.alert_sound=!g_pedit.alert_sound;
   else if(key=="Push")g_pedit.alert_push=!g_pedit.alert_push;
   else if(StringFind(key,"TfDn")==0){int g=Lim((int)StringToInteger(StringSubstr(key,4)),0,FPP_GROUPS-1);g_pedit.group_tf[g]=Lim(g_pedit.group_tf[g]-1,0,20);}
   else if(StringFind(key,"TfUp")==0){int g=Lim((int)StringToInteger(StringSubstr(key,4)),0,FPP_GROUPS-1);g_pedit.group_tf[g]=Lim(g_pedit.group_tf[g]+1,0,20);}
   else if(StringFind(key,"Lbl")==0)g_pedit.label_mode=Lim((int)StringToInteger(StringSubstr(key,3)),0,3);
   else if(key=="FsDn")g_pedit.label_size=Lim(g_pedit.label_size-1,8,24);
   else if(key=="FsUp")g_pedit.label_size=Lim(g_pedit.label_size+1,8,24);
   else if(key=="Merge")g_pedit.merge=!g_pedit.merge;
   else if(key=="Bold")g_pedit.label_bold=!g_pedit.label_bold;
   else if(key=="Pin")g_pedit.pin_left=!g_pedit.pin_left;
   else if(key=="Off")g_pedit.offscreen=!g_pedit.offscreen;
   else if(key=="Hover")g_pedit.hover=!g_pedit.hover;
   else if(key=="Fill")g_pedit.fill=!g_pedit.fill;
   else if(StringFind(key,"Tint")==0)g_pedit.tint=Lim((int)StringToInteger(StringSubstr(key,4)),0,1);
   else if(key=="Range")g_pedit.range_fill=!g_pedit.range_fill;
   else if(StringFind(key,"Flt")==0){g_pfilter=Lim((int)StringToInteger(StringSubstr(key,3)),0,6)-1;g_ppage=0;}
   else if(key=="SortName"){bool d=g_psort==1 && !g_psort_desc;FPPSort(g_pedit,1,d);g_psort=1;g_psort_desc=d;g_ppage=0;rebuild=true;}
   else if(key=="SortTime" || key=="Sort")
     {bool d=key=="SortTime" && g_psort==2 && !g_psort_desc;FPPSort(g_pedit,2,d);g_psort=2;g_psort_desc=d;g_ppage=0;rebuild=true;}
   else if(key=="PageBack")g_ppage=(int)MathMax(0,g_ppage-1);
   else if(key=="PageNext")g_ppage++;
   else if(StringFind(key,"On")==0)
     {int i=PPRowOf(StringSubstr(key,2));if(i<0)return;g_pedit.rows[i].enabled=!g_pedit.rows[i].enabled;rebuild=true;}
   else if(StringFind(key,"Remove")==0)
     {
      int i=PPRowOf(StringSubstr(key,6));
      if(i<0)return;
      for(int k=i;k<g_pedit.count-1;k++)g_pedit.rows[k]=g_pedit.rows[k+1];
      g_pedit.count--;rebuild=true;
     }
   else if(key=="Add")
     {
      if(g_pedit.count>=FPP_MAX){Status("Price point limit reached ("+IntegerToString(FPP_MAX)+").");return;}
      int g=g_pfilter>=0?g_pfilter:4,i=g_pedit.count;
      if(g==3)FPPSet(g_pedit.rows[i],"New FPFVG","","",FPPK_FVG,0,3,570,600,FPPP_BOX|FPPP_CE,clrDodgerBlue,true);
      else
        {
         if(g==0 || g==5)g=4;   // new rows are time windows (gaps and periods are fixed kinds)
         FPPSet(g_pedit.rows[i],"New range","New H","New L",FPPK_WINDOW,0,g,540,600,FPPP_H|FPPP_L,clrDodgerBlue,true);
        }
      g_pedit.rows[i].uid=FPPNewUid(g_pedit);
      g_pedit.count++;
      if(g_pfilter>=0 && g_pfilter!=g)g_pfilter=-1;
      int idx[];int n=PointsFiltered(idx);g_ppage=(n-1)/(int)MathMax(1,g_rows-1);rebuild=true;
     }
   else if(key=="Defaults"){FPPDefaultList(g_pedit);g_ppage=0;g_psort=0;rebuild=true;Status("Default price point list restored. Apply or OK to keep it.");}
   else if(StringFind(key,"P")==0 && StringFind(key,"_")>1)
     {
      int u=StringFind(key,"_");
      int b=(int)StringToInteger(StringSubstr(key,1,u-1)),i=PPRowOf(StringSubstr(key,u+1));
      if(i<0)return;
      b&=FPPAllowed(g_pedit.rows[i].kind);
      if(b==0)return;
      if((g_pedit.rows[i].parts&b)==b)g_pedit.rows[i].parts&=~b;else g_pedit.rows[i].parts|=b;
     }
   else return; // Unknown command: keep the panel (and any edit focus) as it is.
   PPPreview(rebuild);g_ui_dirty=true;
  }
// ---- table dropdowns (kinds 20..23: style, width, label, ends)
void PPDropdown(const int kind,const int row)
  {
   if(!g_peditor || row<0 || row>=g_pedit.count)return;
   string src=kind==20?"N.Style":(kind==21?"N.Width":(kind==22?"N.Label":"N.Ends"));
   int ri=RegFind(UIS(src+PPKey(row)));if(ri<0)return;
   int sx=g_reg[ri].x,sy=g_reg[ri].y,sh=g_reg[ri].h;
   ClosePopup();g_popup=kind;g_popup_row=row;
   string items[];int current=0,w=110;
   if(kind==20){ArrayResize(items,6);items[0]="By role";for(int i=0;i<5;i++)items[i+1]=g_style_names[i];current=g_pedit.rows[row].style+1;w=130;}
   else if(kind==21){ArrayResize(items,5);for(int i=0;i<5;i++)items[i]=IntegerToString(i+1);current=g_pedit.rows[row].width-1;w=48;}
   else if(kind==22)
     {
      ArrayResize(items,5);items[0]="As in Visualization";items[1]="Name";items[2]="Name + day";items[3]="Name + price";items[4]="Off";
      current=g_pedit.rows[row].label;w=150;
     }
   else
     {
      ArrayResize(items,5);items[0]="As in Parameters";items[1]="At the take";items[2]="End of that day";items[3]="End of that week";items[4]="Run to the right edge";
      int e=g_pedit.rows[row].ends;current=e==3?2:(e==4?3:(e==2?4:e));w=170;
     }
   int n=ArraySize(items);
   g_popup_items=n;g_popup_w=U(w);g_popup_h=U(23*n);
   g_popup_x=sx;g_popup_y=sy+sh+U(1);
   if(g_popup_y+g_popup_h>g_height)g_popup_y=(int)MathMax(0,sy-g_popup_h-U(1));
   if(g_popup_x+g_popup_w>g_width)g_popup_x=(int)MathMax(0,g_width-g_popup_w);
   for(int i=0;i<n;i++)
      UIBase(Obj("D."+IntegerToString(i)),OBJ_BUTTON,g_popup_x,g_popup_y+U(23*i),g_popup_w,U(23),items[i],i==current?clrLightSteelBlue:clrWhite,clrBlack,300);
   ChartRedraw();
  }
void PPDropdownChoice(const int choice)
  {
   int i=g_popup_row;
   if(!g_peditor || i<0 || i>=g_pedit.count)return;
   if(g_popup==20)g_pedit.rows[i].style=choice-1;
   else if(g_popup==21)g_pedit.rows[i].width=choice+1;
   else if(g_popup==22)g_pedit.rows[i].label=choice;
   else {int ends[]={0,1,3,4,2};g_pedit.rows[i].ends=ends[Lim(choice,0,4)];}
   PPPreview(false);
  }
// ---- a row's options (popup 16, prefix Q.)
bool FPPDailyKind(FPPoint &p){return FPPCadence(p)!=2 && !FPPWeekly(p);}
int PointMoreHeight(FPPoint &p)
  {
   int h=76+28+28+28+28+40;   // title, kind, group; name on the chart; ray/alert; label weight; hidden; Done
   int k=p.kind;
   if(k==FPPK_WINDOW || k==FPPK_OPEN || k==FPPK_FVG || k==FPPK_OB)h+=28;
   if(k==FPPK_WINDOW || k==FPPK_GAP || k==FPPK_OPEN)h+=28;
   if(FPPDailyKind(p))h+=28;
   if(k==FPPK_FVG || k==FPPK_OB)h+=28;
   return h;
  }
void PointMorePopupBuild()
  {
   int i=g_popup_row,px=g_popup_x,py=g_popup_y;
   if(i<0 || i>=g_pedit.count)return;
   int kind=g_pedit.rows[i].kind;
   UIBase(Obj("Q.BG"),OBJ_RECTANGLE_LABEL,px,py,g_popup_w,g_popup_h,"",clrWhiteSmoke,clrBlack,400);
   QLabel("Title","Options - "+Clip(g_pedit.rows[i].name,34),px+U(10),py+U(7));
   QLabel("Kind",FPPKindText(g_pedit.rows[i]),px+U(10),py+U(27));
   QLabel("GL","Group",px+U(10),py+U(52));
   int gw[]={44,84,104,98,66,48};int bx=px+U(58);
   for(int g=0;g<FPP_GROUPS;g++){QButton("G"+IntegerToString(g),FPPGroupName(g),bx,py+U(48),gw[g],g_pedit.rows[i].group==g);bx+=U(gw[g]+2);}
   int yy=py+U(76);
   if(kind==FPPK_WINDOW || kind==FPPK_OPEN || kind==FPPK_FVG || kind==FPPK_OB)
     {
      QLabel("TL","Type",px+U(10),yy+U(4));
      string tn[]={"Range high/low","Open","FVG","Order block"};int tk[]={FPPK_WINDOW,FPPK_OPEN,FPPK_FVG,FPPK_OB};int tw[]={110,56,50,92};bx=px+U(58);
      for(int t=0;t<4;t++){QButton("K"+IntegerToString(tk[t]),tn[t],bx,yy,tw[t],kind==tk[t]);bx+=U(tw[t]+2);}
      yy+=U(28);
     }
   QLabel("SNL","On the chart",px+U(10),yy+U(4));
   UIBase(Obj("Q.SName"),OBJ_EDIT,px+U(84),yy,U(80),U(22),g_pedit.rows[i].sname,clrWhite,clrBlack,410);
   QLabel("SNH","Short name for labels, e.g. LN (empty: the row's name)",px+U(172),yy+U(4));
   yy+=U(28);
   if(kind==FPPK_WINDOW || kind==FPPK_GAP || kind==FPPK_OPEN)
     {
      QLabel("HNL",kind==FPPK_GAP?"Open line":(kind==FPPK_OPEN?"Line name":"High line"),px+U(10),yy+U(4));
      UIBase(Obj("Q.HName"),OBJ_EDIT,px+U(84),yy,U(100),U(22),g_pedit.rows[i].hname,clrWhite,clrBlack,410);
      if(kind!=FPPK_OPEN)
        {
         QLabel("LNL",kind==FPPK_GAP?"Close line":"Low line",px+U(200),yy+U(4));
         UIBase(Obj("Q.LName"),OBJ_EDIT,px+U(270),yy,U(100),U(22),g_pedit.rows[i].lname,clrWhite,clrBlack,410);
        }
      yy+=U(28);
     }
   if(FPPDailyKind(g_pedit.rows[i]))
     {
      QLabel("SL","Draw on",px+U(10),yy+U(4));
      QButton("S0","Every trading day",px+U(84),yy,130,g_pedit.rows[i].sample==0);
      QButton("S1","Mondays only",px+U(216),yy,104,g_pedit.rows[i].sample==1);
      yy+=U(28);
     }
   QButton("Ray",Tick(g_pedit.rows[i].ray)+"Ray back by default",px+U(10),yy,200,false);
   QButton("Alert",Tick(g_pedit.rows[i].alert)+"Alert when price takes a level",px+U(214),yy,240,false);
   yy+=U(28);
   QLabel("BL","Labels",px+U(10),yy+U(4));
   QButton("B0","As in Visualization",px+U(84),yy,136,g_pedit.rows[i].bold==0);
   QButton("B1","Bold",px+U(222),yy,60,g_pedit.rows[i].bold==1);
   QButton("B2","Regular",px+U(284),yy,70,g_pedit.rows[i].bold==2);
   yy+=U(28);
   if(kind==FPPK_FVG || kind==FPPK_OB)
     {
      QLabel("WL","Window",px+U(10),yy+U(4));
      UIBase(Obj("Q.Len"),OBJ_EDIT,px+U(84),yy,U(40),U(22),IntegerToString(g_pedit.rows[i].len),clrWhite,clrBlack,410);
      QLabel("WL2","min",px+U(128),yy+U(4));
      if(kind==FPPK_OB)
        {
         QLabel("SwL","Swing",px+U(170),yy+U(4));
         UIBase(Obj("Q.Swing"),OBJ_EDIT,px+U(214),yy,U(30),U(22),IntegerToString(g_pedit.rows[i].swing),clrWhite,clrBlack,410);
         QLabel("LkL","Break within",px+U(256),yy+U(4));
         UIBase(Obj("Q.Look"),OBJ_EDIT,px+U(340),yy,U(36),U(22),IntegerToString(g_pedit.rows[i].look),clrWhite,clrBlack,410);
         QLabel("LkL2","min after",px+U(380),yy+U(4));
        }
      yy+=U(28);
     }
   int hidden=PPHiddenCount(g_pedit.rows[i].uid);
   QLabel("HidL",hidden>0?IntegerToString(hidden)+" hidden on this chart":"None hidden on this chart",px+U(10),yy+U(4));
   if(hidden>0)QButton("Show","Show them again",px+U(214),yy,130,false);
   QButton("Done","Done",px+g_popup_w-U(80),py+g_popup_h-U(32),70,false);
   ChartRedraw();
  }
void PointMorePopup(const int i)
  {
   if(!g_peditor || i<0 || i>=g_pedit.count)return;
   ZonePopupFrame(16,i,"N.More"+PPKey(i),520,PointMoreHeight(g_pedit.rows[i]));
   PointMorePopupBuild();
  }
void PPPopupEndEdit(const string name)
  {
   if(g_popup!=16 || StringFind(name,Obj("Q."))!=0 || RegType(name)!=OBJ_EDIT)return;
   int i=g_popup_row;
   if(!g_peditor || i<0 || i>=g_pedit.count)return;
   string key=StringSubstr(name,StringLen(Obj("Q."))),text=ObjectGetString(0,name,OBJPROP_TEXT);
   StringTrimLeft(text);StringTrimRight(text);
   if(key=="HName"){g_pedit.rows[i].hname=StringSubstr(text,0,24);PPPreview(false);return;}
   if(key=="SName"){g_pedit.rows[i].sname=StringSubstr(text,0,16);PPPreview(false);return;}
   if(key=="LName"){g_pedit.rows[i].lname=StringSubstr(text,0,24);PPPreview(false);return;}
   if(key!="Len" && key!="Swing" && key!="Look")return;
   if(!Numeric(text) || StringLen(text)==0)
     {
      int v=key=="Len"?g_pedit.rows[i].len:(key=="Swing"?g_pedit.rows[i].swing:g_pedit.rows[i].look);
      SetText(name,IntegerToString(v));Status("Invalid value; previous setting restored.");return;
     }
   int v=(int)StringToInteger(text);
   if(key=="Len")g_pedit.rows[i].len=Lim(v,1,240);
   else if(key=="Swing")g_pedit.rows[i].swing=Lim(v,1,5);
   else g_pedit.rows[i].look=Lim(v,0,60);
   PPPreview(true);
  }
void PPPopupHarvest()
  {
   if(g_popup!=16)return;
   string keys[]={"HName","LName","SName","Len","Swing","Look"};
   for(int k=0;k<6;k++)PPPopupEndEdit(Obj("Q."+keys[k]));
  }
void PPPopupClick(const string name)
  {
   string key=StringSubstr(name,StringLen(Obj("Q.")));
   int i=g_popup_row;
   if(!g_peditor || i<0 || i>=g_pedit.count){ClosePopup();return;}
   PPPopupHarvest();
   if(key=="Done"){ClosePopup();g_ui_dirty=true;return;}
   bool rebuild=false;
   if(StringFind(key,"G")==0 && StringLen(key)==2){g_pedit.rows[i].group=Lim((int)StringToInteger(StringSubstr(key,1)),0,FPP_GROUPS-1);rebuild=true;}
   else if(StringFind(key,"K")==0 && StringLen(key)==2)
     {
      int k=(int)StringToInteger(StringSubstr(key,1));
      if(k==g_pedit.rows[i].kind || !(k==FPPK_WINDOW || k==FPPK_OPEN || k==FPPK_FVG || k==FPPK_OB))return;
      g_pedit.rows[i].kind=k;
      g_pedit.rows[i].parts=k==FPPK_OPEN?FPPP_O:(k==FPPK_WINDOW?FPPP_H|FPPP_L:FPPP_BOX|FPPP_CE);
      if(k==FPPK_WINDOW && g_pedit.rows[i].end==g_pedit.rows[i].start)g_pedit.rows[i].end=(g_pedit.rows[i].start+30)%1440;
      rebuild=true;
     }
   else if(key=="S0" || key=="S1"){g_pedit.rows[i].sample=key=="S1"?1:0;rebuild=true;}
   else if(key=="Ray")g_pedit.rows[i].ray=!g_pedit.rows[i].ray;
   else if(key=="B0" || key=="B1" || key=="B2")g_pedit.rows[i].bold=(int)StringToInteger(StringSubstr(key,1));
   else if(key=="Alert")g_pedit.rows[i].alert=!g_pedit.rows[i].alert;
   else if(key=="Show"){PPShowHidden(g_pedit.rows[i].uid);Status("Shown again on this chart.");}
   else return;
   PPPreview(rebuild);
   // The table behind is rebuilt (its row may have changed) and the options reopen over it.
   g_ppopup_reopen=i;g_ui_dirty=true;
  }
// ---- presets (same dialog as the Fib and zone presets; two built-ins are generated)
bool PointBuiltin(const string name){return name==FPP_BUILTIN_ICT || name==FPP_BUILTIN_OFF;}
void PointPresetAction()
  {
   string filename="FibonacciPro\\Presets\\"+g_preset_name+".fpt";
   if(g_preset_save)
     {
      if(PointBuiltin(g_preset_name)){PresetMessage("Built-in presets are read-only; choose another name.");return;}
      if(!HarvestPointEdits()){PresetMessage("Correct the invalid values before saving.");return;}
      if(!FPPWriteFile(filename,g_pedit)){PresetMessage("Could not save preset. Check Experts log.");Print("Fibonacci Pro price points preset write error: ",GetLastError());return;}
      if(!ApplyPoints(false)){ClosePopup();Status("Preset saved; applying the price point settings failed.");return;}
      Status("Saved price points preset: "+g_preset_name+".");
      return;
     }
   FPPointConfig loaded;
   if(PointBuiltin(g_preset_name))
     {
      FPPDefaults(loaded);
      if(g_preset_name==FPP_BUILTIN_OFF)for(int i=0;i<loaded.count;i++)loaded.rows[i].enabled=false;
     }
   else if(!FPPReadFile(filename,loaded) && !FPPReadFile(filename+".bak",loaded)){PresetMessage("Preset missing or invalid; current settings retained.");return;}
   g_pedit=loaded;g_ppage=0;g_psort=0;ClosePopup();PPPreview(true);g_ui_dirty=true;
   Status("Loaded "+g_preset_name+". Apply or OK to keep it; Cancel to revert.");
  }

// ---- drawing names: "H1 FVG 2 <arrow>", numbered per timeframe and type (both directions share the count)
// The number in a name of the default pattern "<TF> <type>[ n][ arrow]" (no number counts as 1);
// 0 when the name is not of that pattern (a name the user gave).
int FPNameNumber(const string name,const string base)
  {
   if(StringFind(name,base)!=0)return 0;
   string rest=StringSubstr(name,StringLen(base));
   string up=" "+Glyph(0x25B2),dn=" "+Glyph(0x25BC);
   int lr=StringLen(rest),lu=StringLen(up),ld=StringLen(dn);
   if(lr>=lu && StringSubstr(rest,lr-lu)==up)rest=StringSubstr(rest,0,lr-lu);
   else if(lr>=ld && StringSubstr(rest,lr-ld)==dn)rest=StringSubstr(rest,0,lr-ld);
   if(StringLen(rest)==0)return 1;
   if(StringGetCharacter(rest,0)!=' ' || StringLen(rest)<2 || StringLen(rest)>7)return 0;
   for(int i=1;i<StringLen(rest);i++){ushort c=StringGetCharacter(rest,i);if(c<'0' || c>'9')return 0;}
   return (int)StringToInteger(StringSubstr(rest,1));
  }
string FPTypeBase(FPSetup &s){return FPTfTag(s.source_tf)+" "+FPKindLabel(s);}
// One more than the highest number in use for this timeframe and type.
int FPNextNumber(FPSetup &s)
  {
   string base=FPTypeBase(s);
   int best=0;
   for(int i=0;i<g_count;i++)
     {
      if(g_sets[i].uid==s.uid)continue;
      int n=FPNameNumber(g_sets[i].name,base);
      if(n>best)best=n;
     }
   return best+1;
  }
bool FPIsDefaultName(FPSetup &s){return FPNameNumber(s.name,FPTypeBase(s))>0;}

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
   LoadRisk();
   LoadPoints();
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
   if(FPSOffer())Status("Settings from another terminal are ready: Share, then Import, to use them here.");
   else Status("Panel: "+InpPanelHotkey+" | Duplicate: "+InpDuplicateHotkey+" | Risk: "+InpRiskHotkey+" | Points: "+InpPointsHotkey+" | "+IntegerToString(g_count)+" drawing(s) loaded.");
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

// ---- share settings with other terminals (1.70): one file in MetaTrader's Common folder,
// which every MetaTrader 5 of this Windows user can open. It holds this account's last-used
// drawing style, zone, price point and risk settings, and every preset, as the bytes of
// their own files. An import reads each part with that part's own reader before anything
// is replaced, so a damaged part, or one from a newer version, leaves this account's as it was.
void ShareSay(const string text){g_share_msg=text;Status(text);}
// The bytes of a local file; false when it can't be read (or is too big to be settings).
bool FPSReadBytes(const string filename,uchar &bytes[])
  {
   ArrayResize(bytes,0);
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   ulong size=FileSize(f);
   bool good=size<=(ulong)FPS_MAX_BYTES;
   if(good && size>0){ArrayResize(bytes,(int)size);good=FileReadArray(f,bytes,0,(int)size)==(uint)size;}
   FileClose(f);
   if(!good)ArrayResize(bytes,0);
   return good;
  }
// One part to share: its name in the file and its local file (left out while it is missing).
void FPSAdd(string &names[],string &files[],int &n,const string name,const string file)
  {
   if(StringLen(file)==0 || n>=FPS_MAX_ENTRIES || !FileIsExist(file))return;
   ArrayResize(names,n+1);ArrayResize(files,n+1);
   names[n]=name;files[n]=file;n++;
  }
// A preset that may be shared: "<name>.fpp" (drawings), ".fzp" (zones) or ".fpt" (price
// points). Never a folder, a backup or a temporary file, and never a path.
bool FPSPresetName(const string file)
  {
   int n=StringLen(file);
   if(n<5 || n>80 || SafeName(file)!=file)return false;
   string ext=StringSubstr(file,n-4);
   return ext==".fpp" || ext==".fzp" || ext==".fpt";
  }
// What this account shares: its saved settings and every preset of this terminal.
int FPSGather(string &names[],string &files[])
  {
   int n=0;
   ArrayResize(names,0);ArrayResize(files,0);
   FPSAdd(names,files,n,"style",g_last_store);
   FPSAdd(names,files,n,"zones",g_zstore);
   FPSAdd(names,files,n,"points",g_pstore);
   FPSAdd(names,files,n,"risk",g_rstore);
   string found="";
   long search=FileFindFirst("FibonacciPro\\Presets\\*",found);
   if(search!=INVALID_HANDLE)
     {
      do
        {if(FPSPresetName(found))FPSAdd(names,files,n,"preset/"+found,"FibonacciPro\\Presets\\"+found);}
      while(FileFindNext(search,found));
      FileFindClose(search);
     }
   return n;
  }
string FPSJoin(const string a,const string b){return StringLen(a)==0?b:a+", "+b;}
string FPSPartName(const string name)
  {
   if(name=="style")return "drawing style";
   if(name=="points")return "price points";
   return name;
  }
string FPSPartsText(const bool style,const bool zones,const bool points,const bool risk,const int presets)
  {
   string t="";
   if(style)t=FPSJoin(t,"drawing style");
   if(zones)t=FPSJoin(t,"zones");
   if(points)t=FPSJoin(t,"price points");
   if(risk)t=FPSJoin(t,"risk");
   if(presets>0)t=FPSJoin(t,IntegerToString(presets)+(presets==1?" preset":" presets"));
   return StringLen(t)==0?"nothing":t;
  }
// Reads a shared settings file whole into g_fps_*: 1 read, 0 missing, -1 damaged, -2 written
// by a newer version. Unless it returns 1, nothing of the file is kept.
int FPSLoad(const string filename,const int common)
  {
   g_fps_n=0;ArrayResize(g_fps_data,0);g_fps_version="";g_fps_time=0;
   if(!FileIsExist(filename,common))return 0;
   int f=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE|FILE_SHARE_READ|common);
   if(f==INVALID_HANDLE)return -1;
   bool good=FileReadInteger(f)==FPS_MAGIC;
   int schema=good?FileReadInteger(f):0;
   if(good && schema>FPS_SCHEMA){FileClose(f);return -2;}
   string version="";
   good=good && schema>=1 && RText(f,version,16);
   long time=good?FileReadLong(f):0;
   int n=good?FileReadInteger(f):0;
   good=good && n>=0 && n<=FPS_MAX_ENTRIES;
   if(good){ArrayResize(g_fps_names,n);ArrayResize(g_fps_start,n);ArrayResize(g_fps_size,n);}
   int total=0;
   for(int i=0;good && i<n;i++)
     {
      good=RText(f,g_fps_names[i],100);
      int size=good?FileReadInteger(f):-1;
      good=good && size>=0 && size<=FPS_MAX_BYTES && (long)FileTell(f)+size<=(long)FileSize(f);
      if(!good)break;
      g_fps_start[i]=total;g_fps_size[i]=size;
      if(size>0)
        {
         ArrayResize(g_fps_data,total+size,65536);
         good=FileReadArray(f,g_fps_data,total,size)==(uint)size;
        }
      total+=size;
     }
   good=good && FileReadInteger(f)==FPS_END && FileTell(f)==FileSize(f);
   FileClose(f);
   if(!good){ArrayResize(g_fps_data,0);return -1;}
   g_fps_n=n;g_fps_version=version;g_fps_time=time;
   return 1;
  }
// Writes the shared file (the previous one is kept as .bak): the number of parts written,
// 0 when there is nothing to share, -1 when it failed (the shared file is then unchanged).
int FPSExport()
  {
   string names[];
   string files[];
   int n=FPSGather(names,files);
   if(n==0){ShareSay("Nothing to export yet: no saved settings or presets on this account.");return 0;}
   FolderCreate("FibonacciPro",FILE_COMMON);
   string shared=FPS_FILE,temporary=shared+".tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE|FILE_COMMON);
   if(f==INVALID_HANDLE)
     {
      Print("Fibonacci Pro: could not create the shared settings file, error ",GetLastError());
      ShareSay("Export failed: the shared settings file could not be written.");return -1;
     }
   ResetLastError();
   FileWriteInteger(f,FPS_MAGIC);FileWriteInteger(f,FPS_SCHEMA);WText(f,FP_VERSION);FileWriteLong(f,(long)TimeLocal());
   FileWriteInteger(f,n);
   bool good=true,style=false,zones=false,points=false,risk=false;
   int presets=0;
   for(int i=0;i<n && good;i++)
     {
      uchar bytes[];
      good=FPSReadBytes(files[i],bytes);
      if(!good){Print("Fibonacci Pro: could not read ",files[i]," for the shared settings file.");break;}
      int size=ArraySize(bytes);
      WText(f,names[i]);FileWriteInteger(f,size);
      if(size>0 && FileWriteArray(f,bytes,0,size)!=(uint)size)good=false;
      if(StringFind(names[i],"preset/")==0)presets++;
      else if(names[i]=="style")style=true;
      else if(names[i]=="zones")zones=true;
      else if(names[i]=="points")points=true;
      else risk=true;
     }
   FileWriteInteger(f,FPS_END);FileFlush(f);int error=GetLastError();FileClose(f);
   // Read back in full before it replaces the shared file.
   if(good && error==0)good=FPSLoad(temporary,FILE_COMMON)==1 && g_fps_n==n;
   if(good && FileIsExist(shared,FILE_COMMON))good=FileCopy(shared,FILE_COMMON,shared+".bak",FILE_REWRITE|FILE_COMMON);
   if(good)good=FileMove(temporary,FILE_COMMON,shared,FILE_REWRITE|FILE_COMMON);
   if(!good)
     {
      FileDelete(temporary,FILE_COMMON);
      ShareSay("Export failed; the shared settings file is unchanged. See the Experts log.");return -1;
     }
   ShareSay("Exported "+FPSPartsText(style,zones,points,risk,presets)+".");
   return n;
  }
// Entry i of the loaded file, in a local temporary file for its part's reader ("" failed).
string FPSTempFile(const int i)
  {
   string temporary="FibonacciPro\\import.tmp."+IntegerToString(ChartID());
   int f=FileOpen(temporary,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE)return "";
   bool good=g_fps_size[i]==0 || FileWriteArray(f,g_fps_data,g_fps_start[i],g_fps_size[i])==(uint)g_fps_size[i];
   FileClose(f);
   if(!good){FileDelete(temporary);return "";}
   return temporary;
  }
// One part from its temporary file: read with its own reader, then saved as this account's
// (a preset: into this terminal's presets). A part that can't be read or saved changes nothing.
bool FPSImportPart(const string name,const string file,const string temporary)
  {
   if(name=="style")
     {
      FPSetup s;FPClearLevels(s);
      if(!ReadPreset(temporary,s) || !WritePreset(g_last_store,s))return false;
      g_last_config=s;g_has_last_config=true;g_last_config_persisted=true;
      return true;
     }
   if(name=="zones")
     {
      FPZoneConfig c;FPZClear(c);
      if(!FPZReadFile(temporary,c))return false;
      // The broker's clock belongs to the broker: by default this account keeps its own.
      if(g_share_clock){c.broker_mode=g_zcfg.broker_mode;c.broker_gmt=g_zcfg.broker_gmt;}
      FPZoneConfig keep=g_zcfg;
      g_zcfg=c;
      if(!SaveZones()){g_zcfg=keep;return false;}
      g_zact=g_zcfg;g_zocc_dirty=true;g_zone_resolve=0;
      return true;
     }
   if(name=="points")
     {
      FPPointConfig c;FPPClear(c);
      if(!FPPReadFile(temporary,c))return false;
      FPPointConfig keep=g_pcfg;
      g_pcfg=c;
      if(!SavePoints()){g_pcfg=keep;return false;}
      g_pact=g_pcfg;g_pocc_dirty=true;
      return true;
     }
   if(name=="risk")
     {
      FPRiskConfig c;FPRDefaults(c);
      if(!FPRReadFile(temporary,c))return false;
      FPRiskConfig keep=g_rcfg;
      g_rcfg=c;
      if(!SaveRisk()){g_rcfg=keep;return false;}
      g_redit=g_rcfg;RiskReset();
      return true;
     }
   string dest="FibonacciPro\\Presets\\"+file,ext=StringSubstr(file,StringLen(file)-4);
   if(ext==".fpp"){FPSetup s;FPClearLevels(s);return ReadPreset(temporary,s) && WritePreset(dest,s);}
   if(ext==".fzp"){FPZoneConfig c;FPZClear(c);return FPZReadFile(temporary,c) && FPZWriteFile(dest,c);}
   FPPointConfig c;FPPClear(c);
   return FPPReadFile(temporary,c) && FPPWriteFile(dest,c);
  }
// Imports the parts chosen in g_share_parts. Presets of the same name are replaced (kept as
// .bak), other presets stay; replaced settings files keep a .bak too. A part that can't be
// read or saved is reported and left as it was.
bool FPSImport()
  {
   if((g_share_parts&15)==0){ShareSay("Choose what to import first.");return false;}
   int got=FPSLoad(FPS_FILE,FILE_COMMON);
   if(got==0){ShareSay("No shared settings file yet: export one first (Share, Export).");return false;}
   if(got==-2){ShareSay("The shared settings file is from a newer Fibonacci Pro: update this one first.");return false;}
   if(got<0){ShareSay("The shared settings file is damaged; nothing was imported.");return false;}
   bool style=false,zones=false,points=false,risk=false;
   int presets=0,bad_presets=0;
   string skipped="";
   for(int i=0;i<g_fps_n;i++)
     {
      string name=g_fps_names[i];
      bool preset=StringFind(name,"preset/")==0;
      int part=(preset || name=="style")?FPS_STYLES:(name=="zones"?FPS_ZONES:(name=="points"?FPS_POINTS:(name=="risk"?FPS_RISK:0)));
      if(part==0 || (g_share_parts&part)==0)continue;      // not chosen, or a part this version doesn't know
      string file=preset?StringSubstr(name,7):"";
      if(preset && !FPSPresetName(file)){bad_presets++;continue;}
      string temporary=FPSTempFile(i);
      bool ok=StringLen(temporary)>0 && FPSImportPart(name,file,temporary);
      if(StringLen(temporary)>0)FileDelete(temporary);
      if(!ok){if(preset)bad_presets++;else skipped=FPSJoin(skipped,FPSPartName(name));continue;}
      if(preset)presets++;
      else if(name=="style")style=true;
      else if(name=="zones")zones=true;
      else if(name=="points")points=true;
      else risk=true;
     }
   g_dirty=true;g_ui_dirty=true;
   if(bad_presets>0)skipped=FPSJoin(skipped,IntegerToString(bad_presets)+(bad_presets==1?" preset":" presets"));
   string text="Imported "+FPSPartsText(style,zones,points,risk,presets)+".";
   if(StringLen(skipped)>0)text+=" Not imported, kept as they were: "+skipped+".";
   ShareSay(text);
   return style || zones || points || risk || presets>0;
  }
// A fresh account (nothing saved yet) on a computer that has a shared settings file.
bool FPSOffer()
  {return !FileIsExist(g_zstore) && !FileIsExist(g_pstore) && !FileIsExist(g_rstore) && !FileIsExist(g_last_store) && FileIsExist(FPS_FILE,FILE_COMMON);}
string FPSFolder(){return TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\FibonacciPro";}
// The shared file, as the Share popup describes it.
string FPSFileText()
  {
   int got=FPSLoad(FPS_FILE,FILE_COMMON);
   if(got==0)return "No shared settings file yet.";
   if(got==-2)return "The shared file is from a newer Fibonacci Pro.";
   if(got<0)return "The shared file is damaged.";
   int presets=0;bool style=false,zones=false,points=false,risk=false;
   for(int i=0;i<g_fps_n;i++)
     {
      if(StringFind(g_fps_names[i],"preset/")==0)presets++;
      else if(g_fps_names[i]=="style")style=true;
      else if(g_fps_names[i]=="zones")zones=true;
      else if(g_fps_names[i]=="points")points=true;
      else if(g_fps_names[i]=="risk")risk=true;
     }
   return Clip("Saved "+TimeToString((datetime)g_fps_time,TIME_DATE|TIME_MINUTES)+" ("+g_fps_version+"): "+FPSPartsText(style,zones,points,risk,presets),90);
  }

// ---- the Share button and popup (popup 17, prefix Q.)
void UpdateShareButton()
  {
   if(g_hidden || !g_owner)return;
   Button("T.Share","Share",g_toolbar_x+U(FP_TOOLBAR_WIDTH-284),g_toolbar_y+U(1),60,18);
   Tooltip("T.Share","Use these settings in other MetaTrader 5 terminals: export them to a shared file, or import it");
  }
bool HitShareButton(const int x,const int y)
  {return !g_hidden && x>=g_toolbar_x+U(FP_TOOLBAR_WIDTH-284) && x<=g_toolbar_x+U(FP_TOOLBAR_WIDTH-224) && y>=g_toolbar_y+U(1) && y<=g_toolbar_y+U(19);}
void OpenShare()
  {
   if(g_editor){Status("Finish or cancel Properties first.");return;}
   if(g_zeditor){Status("Close the Zones window first.");return;}
   if(g_reditor){Status("Close the Risk window first.");return;}
   if(g_peditor){Status("Close the Price points window first.");return;}
   if(g_drag!=0 || g_armed)CancelDrag();
   // A rebuild of the UI left for a later frame closes every popup (RefreshFrame), so one
   // still pending (or the list closing) is done now, before the popup opens.
   bool rebuild=g_ui_dirty || g_list;
   ClosePopup();g_list=false;
   if(rebuild)BuildUI();
   g_popup=17;g_popup_row=-1;g_share_confirm_until=0;g_share_msg="";
   g_popup_w=U(FPS_POPUP_W);g_popup_h=U(FPS_POPUP_H);
   g_popup_x=Lim(g_toolbar_x,0,(int)MathMax(0,g_width-g_popup_w));
   // Below the status line (and the risk bar), which would otherwise be drawn over it.
   g_popup_y=g_toolbar_y+U(FP_TOOLBAR_HEIGHT+26)+(RiskBarShown()?U(26):0);
   if(g_popup_y+g_popup_h>g_height)g_popup_y=g_toolbar_y-g_popup_h-U(4);
   g_popup_y=Lim(g_popup_y,0,(int)MathMax(0,g_height-g_popup_h));
   SharePopupBuild();
  }
void SharePopupBuild()
  {
   if(g_popup!=17)return;
   int px=g_popup_x,py=g_popup_y;
   UIBase(Obj("Q.BG"),OBJ_RECTANGLE_LABEL,px,py,g_popup_w,g_popup_h,"",clrWhiteSmoke,clrBlack,400);
   QLabel("Title","Share settings with other MetaTrader 5 terminals",px+U(10),py+U(7));
   QLabel("Info","One file that every MetaTrader 5 on this computer can open.",px+U(10),py+U(28));
   QButton("Export","Export",px+U(10),py+U(52),80,false);
   QLabel("ExpL","Saves this account's settings and all presets into it",px+U(98),py+U(56));
   QLabel("File",FPSFileText(),px+U(10),py+U(84));
   QLabel("ImpL","Import",px+U(10),py+U(112));
   QButton("S1","Styles & presets",px+U(62),py+U(108),112,(g_share_parts&FPS_STYLES)!=0);
   QButton("S2","Zones",px+U(176),py+U(108),60,(g_share_parts&FPS_ZONES)!=0);
   QButton("S4","Price points",px+U(238),py+U(108),88,(g_share_parts&FPS_POINTS)!=0);
   QButton("S8","Risk",px+U(328),py+U(108),50,(g_share_parts&FPS_RISK)!=0);
   QButton("Clock","Keep this account's broker clock (Zones)",px+U(62),py+U(136),250,g_share_clock);
   QButton("Import",GetTickCount64()<=g_share_confirm_until?"Click again":"Import",px+U(10),py+U(166),80,false);
   QLabel("ImpH","Replaces this account's chosen settings; backups are kept",px+U(98),py+U(170));
   QLabel("PathL","Folder",px+U(10),py+U(204));
   // An ordinary edit box, so its text can be selected and copied; anything typed into it is
   // undone when it loses focus (OnChartEvent).
   UIBase(Obj("Q.Path"),OBJ_EDIT,px+U(62),py+U(200),g_popup_w-U(72),U(22),FPSFolder(),clrWhite,clrBlack,410);
   ObjectSetString(0,Obj("Q.Path"),OBJPROP_TOOLTIP,"Select the path and press Ctrl+C to copy it");
   QLabel("PathH","On another computer, copy FibonacciPro.settings into this folder there.",px+U(10),py+U(230));
   QLabel("Msg",Clip(g_share_msg,90),px+U(10),py+U(256));
   QButton("Done","Done",px+g_popup_w-U(80),py+g_popup_h-U(30),70,false);
   ChartRedraw();
  }
void SharePopupClick(const string name)
  {
   string key=StringSubstr(name,StringLen(Obj("Q.")));
   if(key!="Import")g_share_confirm_until=0;
   if(key=="Done"){ClosePopup();return;}
   if(key=="Export")FPSExport();
   else if(key=="Import")
     {
      ulong now=GetTickCount64();
      if((g_share_parts&15)!=0 && now>g_share_confirm_until)
        {g_share_confirm_until=now+5000;ShareSay("Click Import again to replace this account's chosen settings with the file's.");}
      else {g_share_confirm_until=0;FPSImport();}
     }
   else if(key=="S1" || key=="S2" || key=="S4" || key=="S8")g_share_parts^=(int)StringToInteger(StringSubstr(key,1));
   else if(key=="Clock")g_share_clock=!g_share_clock;
   else return;
   // An import changes what the toolbar shows. That rebuild is done now: left for a later
   // frame, it would close this popup and its message with it.
   if(g_ui_dirty)BuildUI();
   SharePopupBuild();
  }

int OnInit()
  {
   if(!ParseHotkey(InpPanelHotkey,g_panel_key,g_panel_ctrl,g_panel_shift,g_panel_alt) || !ParseHotkey(InpDuplicateHotkey,g_duplicate_key,g_duplicate_ctrl,g_duplicate_shift,g_duplicate_alt)
      || !ParseHotkey(InpZonesHotkey,g_zones_key,g_zones_ctrl,g_zones_shift,g_zones_alt) || !ParseHotkey(InpRiskHotkey,g_risk_key,g_risk_ctrl,g_risk_shift,g_risk_alt)
      || !ParseHotkey(InpPointsHotkey,g_points_key,g_points_ctrl,g_points_shift,g_points_alt) || ShortcutsClash())
     {Print("Fibonacci Pro: use five different shortcuts, e.g. Ctrl+Shift+H, Ctrl+Shift+D, Ctrl+Shift+K, Ctrl+Shift+R and Ctrl+Shift+L (letters, digits or F1..F12).");return INIT_PARAMETERS_INCORRECT;}
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
   FPInstallBuiltinsOnce();
   g_last_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".last.fpp";
   g_zstore="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".zones";
   // Risk settings belong to the account: every chart and workspace of it shares them.
   g_rstore="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".risk";
   g_pstore="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(InpWorkspace)+".points";
   g_store="FibonacciPro\\"+SafeName(AccountInfoString(ACCOUNT_SERVER))+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeName(_Symbol)+"_"+SafeName(InpWorkspace)+"_"+key+".bin";
   g_pflag_store=g_store+".pts";   // price points rayed back or hidden on this chart
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
   PPTick(now);
   RiskTick(now);
   // MT5 can deliver a mouse event before its chart projection has updated.
   // Poll each frame during chart panning and for 150 ms after the last pan event.
   if(g_view_probe || now<g_fast_view_until || now-g_last_view>=200)
     {if(ViewChanged())g_dirty=true;g_last_view=now;g_view_probe=false;}
   bool changed=false;
   if(g_dirty && now>=g_render_retry_after){Render();changed=true;}
   // Leave a short grace period for queued native OBJECT_CLICK events.
   if(g_ui_dirty && !g_prev_down && !g_toolbar_drag && g_drag==0 && !g_slider_drag && !g_zdrag && !g_ppdrag && g_rdrag==0 && now>=g_ui_defer_until)
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
      else if(g_popup==0){EndEdit(sparam);ZEndEdit(sparam);REndEdit(sparam);PEndEdit(sparam);}
      else if(g_popup==16)PPPopupEndEdit(sparam);
      else if(g_popup==17)SharePopupBuild();
      return;
     }
   if(id==CHARTEVENT_MOUSE_WHEEL){ListWheel((int)(short)lparam,(int)(short)(lparam>>16),(int)dparam);RefreshFrame();return;}
   if(id==CHARTEVENT_CLICK)
     {if(g_prev_down || g_drag!=0 || g_toolbar_drag || g_zdrag || g_ppdrag || g_rdrag!=0)FinishPointer((int)lparam,(int)dparam);return;}
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(g_prev_down || g_drag!=0 || g_toolbar_drag || g_zdrag || g_ppdrag || g_rdrag!=0)FinishPointer((int)lparam,(int)dparam);
      if(StringFind(sparam,g_prefix)==0)Click(sparam);
      else if(StringFind(sparam,"FP5.")!=0 && !g_editor && g_drag==0 && g_selected>=0){g_selected=-1;g_dirty=true;g_ui_dirty=true;}
      RefreshFrame();
      return;
     }
   if(id==CHARTEVENT_KEYUP)
     {if((int)lparam==g_panel_key)g_panel_key_held=false;if((int)lparam==g_duplicate_key)g_duplicate_key_held=false;if((int)lparam==g_zones_key)g_zones_key_held=false;if((int)lparam==g_risk_key)g_risk_key_held=false;if((int)lparam==g_points_key)g_points_key_held=false;return;}
   if(id==CHARTEVENT_KEYDOWN)
     {
      int key=(int)lparam;
      if(key==27)
        {
         // Innermost first: a drag, a measurement being made, a popup, a window, the list,
         // then a finished measurement.
         if(g_zdrag || g_ppdrag)CancelDrag();
         else if(g_rdrag!=0 || g_risk.armed)RiskCancel();
         else if(g_popup!=0)ClosePopup();
         else if(g_editor)CloseEditor();
         else if(g_zeditor)CloseZones();
         else if(g_reditor)CloseRisk();
         else if(g_peditor)ClosePoints();
         else if(g_list){g_list=false;g_ui_dirty=true;}
         else if(g_psel_uid!=0)PPClearSel();
         else if(g_risk.active)RiskClear();
         else CancelDrag();
         HideTip();return;
        }
      bool ctrl=(TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL)&0x8000)!=0;
      bool shift=(TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT)&0x8000)!=0;
      bool alt=(TerminalInfoInteger(TERMINAL_KEYSTATE_MENU)&0x8000)!=0;
      // Bare-letter shortcuts must not fire while the user types properties.
      if((g_editor || g_zeditor || g_reditor || g_peditor || g_list) && !ctrl && !alt)return;
      if(FPShortcutMatch(key,g_panel_key,ctrl,shift,alt,g_panel_ctrl,g_panel_shift,g_panel_alt))
        {if(!g_panel_key_held){g_panel_key_held=true;ToggleUI();}return;}
      if(FPShortcutMatch(key,g_zones_key,ctrl,shift,alt,g_zones_ctrl,g_zones_shift,g_zones_alt))
        {if(!g_zones_key_held){g_zones_key_held=true;ToggleZonesShown();}return;}
      if(FPShortcutMatch(key,g_risk_key,ctrl,shift,alt,g_risk_ctrl,g_risk_shift,g_risk_alt))
        {if(!g_risk_key_held){g_risk_key_held=true;RiskButton();}return;}
      if(FPShortcutMatch(key,g_points_key,ctrl,shift,alt,g_points_ctrl,g_points_shift,g_points_alt))
        {if(!g_points_key_held){g_points_key_held=true;TogglePointsShown();}return;}
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
