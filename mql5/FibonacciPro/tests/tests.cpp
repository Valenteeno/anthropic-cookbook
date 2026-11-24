// Behavioural tests for Fibonacci_Pro_13.mq5 (1.67), translated to fp5.cpp by translate.py.
#define TEST_OWN_XY
#define TEST_OWN_FILES
#define TEST_OWN_TIME
#define TEST_OWN_RATES
#define TEST_OWN_ALERTS
#define TEST_OWN_OBJGET
#define TEST_OWN_CANVAS
#define TEST_OWN_XYTP
#define TEST_OWN_MARKET
#include "fp5.cpp"
#include <cstdio>
#include <cstring>
#include <map>
#include <algorithm>
#include <cstdlib>
#include <array>
#include "mql5_defaults.h"
#include "test_common.h"
// --- stubs the tests observe
string _Symbol="EURUSD";int _Digits=5;double _Point=0.00001;int _Period=PERIOD_H1;
// Line-canvas fills are recorded on demand, so a test can see which lines were drawn.
struct RecRect{int x0,y0,x1,y1;uint c;bool fill;};static std::vector<RecRect> g_rects;static bool g_rec=false;
void CCanvas::FillRectangle(int x1,int y1,int x2,int y2,uint c)
  {if(g_rec && (this==&g_line_canvas || this==&g_fill_canvas))g_rects.push_back({x1,y1,x2,y2,c,this==&g_fill_canvas});}
static int RowPieces(int y,int xa,int xb){int n=0;for(auto& r:g_rects)if(!r.fill && r.y0==y && r.y1==y && r.x1>=xa && r.x0<=xb)n++;return n;}
// Colour left on the shading canvas at (x,y): the last recorded fill there wins, as on a canvas.
static uint FillAt(int x,int y){uint c=0;for(auto& r:g_rects)if(r.fill && r.x0<=x && x<=r.x1 && r.y0<=y && y<=r.y1)c=r.c;return c;}
// Reference ARGB of an MQL colour (0x00BBGGRR) and reference "over" of two ARGB colours.
static uint RefARGB(color c,int a){return ((uint)a<<24)|((uint)(c&255)<<16)|((uint)((c>>8)&255)<<8)|(uint)((c>>16)&255);}
static uint RefOver(uint lower,uint upper)
  {
   double al=(lower>>24)/255.0,au=(upper>>24)/255.0,a=au+al*(1-au);
   uint out=(uint)std::lround(a*255)<<24;
   for(int sh=0;sh<=16;sh+=8){double c=(((upper>>sh)&255)*au+((lower>>sh)&255)*al*(1-au))/a;out|=(uint)std::lround(c)<<sh;}
   return out;
  }
static bool Near(uint a,uint b,int tol=2){for(int sh=0;sh<=24;sh+=8)if(std::abs((int)((a>>sh)&255)-(int)((b>>sh)&255))>tol)return false;return true;}
// Projection: 1 px per minute from g_xy_t0; price 1.2 at y=0, 3000 px per price unit.
static long g_xy_t0=0;
bool ChartTimePriceToXY(long,int,datetime t,double p,int& x,int& y){x=(int)((t-g_xy_t0)/60);y=(int)std::lround((1.2-p)*3000);return true;}
bool ChartXYToTimePrice(long,int x,int y,int& s,datetime& t,double& p){s=0;t=(datetime)(g_xy_t0+60L*x);p=1.2-y/3000.0;return true;}
static std::vector<MqlRates> g_bars;
// M1 bars as given; H1 requests get them grouped into hours (as the terminal builds them).
static long TfSec(ENUM_TIMEFRAMES tf){return tf==PERIOD_H1?3600:60;}
int CopyRates(const string&,ENUM_TIMEFRAMES tf,datetime from,datetime to,MQLArr<MqlRates>& r)
  {
   r.v.clear();long sec=TfSec(tf);
   for(auto& b:g_bars)
     {
      long bt=(b.time/sec)*sec;
      if(bt<from || bt>to)continue;
      if(!r.v.empty() && r.v.back().time==bt){MqlRates& a=r.v.back();a.high=std::max(a.high,b.high);a.low=std::min(a.low,b.low);a.close=b.close;}
      else {MqlRates a=b;a.time=bt;r.v.push_back(a);}
     }
   return (int)r.v.size();
  }
// From a time backwards: the `count` bars up to the one at or before `start`, oldest first.
int CopyRates(const string& s,ENUM_TIMEFRAMES tf,datetime start,int count,MQLArr<MqlRates>& r)
  {
   MQLArr<MqlRates> all;CopyRates(s,tf,(datetime)0,start,all);
   r.v.clear();int n=(int)all.v.size();
   for(int i=std::max(0,n-count);i<n;i++)r.v.push_back(all.v[i]);
   return (int)r.v.size();
  }
static long NY(int y,int m,int d,int hh,int mm){return FPDaysFromCivil(y,m,d)*86400+hh*3600+mm*60;}
static int FindZone(FPZoneConfig& c,const string& name){for(int i=0;i<c.count;i++)if(c.zones[i].name==name)return i;return -1;}
static int MarkOfZone(int z){for(int k=0;k<g_zmark_n;k++)if(g_zocc[g_zvis[g_zmark[k].vis].occ].zone==z)return k;return -1;}
static void MakeFib(FPSetup &s,const int uid,const string name,const bool hline,const ENUM_TIMEFRAMES tf)
  {
   s.uid=uid;s.name=name;s.description="";s.hline=hline;s.source_tf=tf;s.visible_mask=FP_ALL_TF_MASK;s.visibility_mode=0;
   s.ta=60000;s.tb=120000;s.pa=1.2;s.pb=1.1;s.left=60000;s.right=120000;s.ray_left=false;s.ray_right=false;
   s.diagonal=true;s.labels=true;s.label_v=0;s.label_h=0;s.label_float=true;s.anchors_locked=false;s.base_color=clrRed;
   s.fill=false;s.opacity=12;s.count=3;double r[]={0,.5,1};
   for(int i=0;i<3;i++){s.levels[i].enabled=true;s.levels[i].value=r[i];s.levels[i].description=FP_DEFAULT_TEXT;s.levels[i].style=0;s.levels[i].width=1;s.levels[i].ink=clrBlue;}
  }
// Synthetic M1 bars: a gentle wave plus a spike at a known minute.
static void MakeBars(long from_server,long to_server)
  {
   g_bars.clear();
   for(long t=from_server;t<=to_server;t+=60)
     {
      MqlRates r{};r.time=t;double base=1.1000+0.0020*std::sin(t/7200.0);
      r.open=base;r.close=base+0.00005;r.high=base+0.00010;r.low=base-0.00010;g_bars.push_back(r);
     }
  }

// ---- price points (1.67): a broker on New York + 7 h, flat at 1.1000 with known candles
static datetime SV(int y,int m,int d,int hh,int mm){return (datetime)FPNYToServer(NY(y,m,d,hh,mm),1,2);}
static int FindRow(FPPointConfig& c,const string& n){for(int i=0;i<c.count;i++)if(c.rows[i].name==n)return i;return -1;}
static int OccOf(int row,long key){for(int i=0;i<g_pocc_n;i++)if(g_pocc[i].row==row && g_pocc[i].key==key)return i;return -1;}
static int OccCount(int row){int n=0;for(int i=0;i<g_pocc_n;i++)if(g_pocc[i].row==row)n++;return n;}
static int LineOf(int occ,int part){for(int k=0;k<g_ppline_n;k++)if(g_ppline[k].occ==occ && g_ppline[k].part==part)return k;return -1;}
static int LabelWith(const string& t){for(int k=0;k<g_pplabel_n;k++)if(g_pplabel[k].w>0 && g_pplabel[k].text.find(t)!=string::npos)return k;return -1;}
static bool PPHasLine(const std::vector<string>& v,const string& t){for(auto& s:v)if(s==t)return true;return false;}
static void PPSetBar(int y,int m,int d,int hh,int mm,double o,double h,double l,double c)
  {
   datetime t=SV(y,m,d,hh,mm);
   for(auto& b:g_bars)if(b.time==t){b.open=o;b.high=h;b.low=l;b.close=c;return;}
   if(!g_bars.empty() && t<=g_bars.back().time){std::printf("no bar at %d.%d %02d:%02d\n",m,d,hh,mm);fails++;}
  }
// Every minute from Friday 13 Nov 2026 09:00 New York to `to`, without the weekend and the daily 17:00-18:00 break.
static void PPMakeBars(datetime to)
  {
   g_bars.clear();
   for(long ny=NY(2026,11,13,9,0);;ny+=60)
     {
      datetime t=(datetime)FPNYToServer(ny,1,2);
      if(t>to)break;
      long day=FPFloorDiv(ny,86400);int dow=FPDow(day),mins=(int)((ny-day*86400)/60);
      bool weekend=(dow==5 && mins>=1020) || dow==6 || (dow==0 && mins<1080);
      if(weekend || (mins>=1020 && mins<1080))continue;
      MqlRates r{};r.time=t;r.open=1.1;r.close=1.1;r.high=1.1001;r.low=1.0999;g_bars.push_back(r);
     }
   PPSetBar(2026,11,15,18,0,1.0990,1.0992,1.0988,1.0991);   // Sunday's open: a gap down from Friday's 1.1000 (NWOG)
   PPSetBar(2026,11,15,18,1,1.0991,1.1000,1.0991,1.1000);   // filled at once
   PPSetBar(2026,11,16,10,23,1.1,1.1030,1.0999,1.1);        // Monday's high
   PPSetBar(2026,11,16,18,0,1.1010,1.1012,1.1008,1.1009);   // Monday evening's reopen: a gap up (Tuesday's NDOG)
   PPSetBar(2026,11,16,18,1,1.1009,1.1009,1.1004,1.1004);   // through its CE
   PPSetBar(2026,11,16,18,2,1.1004,1.1004,1.0999,1.1);      // filled
   PPSetBar(2026,11,17,5,12,1.1,1.1050,1.0999,1.1);         // London's high
   PPSetBar(2026,11,17,9,30,1.1020,1.1022,1.1018,1.1019);   // the 09:30 open gaps up (ORG) ...
   PPSetBar(2026,11,17,9,31,1.1019,1.1019,1.0999,1.1);      // ... and fills: a bearish FVG from 09:30 to 09:32
   PPSetBar(2026,11,17,9,47,1.1,1.1001,1.0950,1.1);         // London's low
   PPSetBar(2026,11,17,12,30,1.1,1.1050,1.0999,1.1);        // touches London's high: not taken
   PPSetBar(2026,11,17,13,5,1.1,1.1051,1.0999,1.1);         // takes it
   PPSetBar(2026,11,17,13,35,1.1,1.1003,1.0999,1.1);        // a swing high in the PM window
   PPSetBar(2026,11,17,13,33,1.1,1.1002,1.0999,1.1002);     // a close above the flat highs: no break (flat candles are no swings)
   PPSetBar(2026,11,17,13,37,1.1,1.1004,1.0999,1.1);        // a wick above it, no close: no break (a new swing high)
   PPSetBar(2026,11,17,13,39,1.1001,1.1001,1.0998,1.0998);  // the last down candle (the order block) ...
   PPSetBar(2026,11,17,13,40,1.0998,1.1000,1.0998,1.1000);  // ... an up candle ...
   PPSetBar(2026,11,17,13,41,1.1000,1.1006,1.0999,1.1005);  // ... and a close above the swing: the break
  }
static void PPScanAll(datetime now){for(int pass=0;pass<20;pass++)for(int i=0;i<g_pocc_n;i++)PPScan(g_pocc[i],g_pact.rows[g_pocc[i].row].kind,now);}

int main()
  {
   g_prefix="FP5.Main.abc123.";g_scale=1.0;g_tf=11;g_width=1000;g_height=600;

   // ---- 1.61 behaviour kept
   CHECK(InpMaximumSetups==1000 && FP_MAX_SETUPS==1000 && InpFrameMilliseconds==8);
   CHECK(FPLabelX(-200,300,-200,300,50,1000,0,false,false,true,3)==3);
   CHECK((FPAdaptMask(((long)1<<4)|((long)1<<11),11,14,0)&((long)1<<14))!=0);
   g_count=4;MakeFib(g_sets[0],10,"zeta fib",false,PERIOD_H1);MakeFib(g_sets[1],11,"Alpha line",true,PERIOD_M5);
   MakeFib(g_sets[2],12,"beta",false,PERIOD_D1);MakeFib(g_sets[3],13,"Gamma line",true,PERIOD_H1);
   g_list_sort=1;g_list_desc=false;g_list_key="";ListRebuild();
   CHECK(g_list_n==4 && g_list_idx[0]==1 && g_list_idx[3]==0);
   g_count=0;

   // ---- hotkeys: three distinct shortcuts
   int key=0;bool c=false,s=false,a=false;
   CHECK(ParseHotkey(InpZonesHotkey,key,c,s,a) && key=='K' && c && s && !a);
   g_panel_key='H';g_duplicate_key='D';g_zones_key='K';CHECK(!ShortcutsClash());
   g_zones_key='H';CHECK(ShortcutsClash());g_zones_key='K';

   // ---- calendar and daylight saving
   CHECK(FPDaysFromCivil(1970,1,1)==0 && FPDow(0)==4);
   long d17=FPDaysFromCivil(2026,11,17);CHECK(FPDow(d17)==2);   // Tuesday
   {int y=0,m=0,d=0;FPCivilFromDays(d17,y,m,d);CHECK(y==2026 && m==11 && d==17);}
   {bool ok=true;for(long z=-800;z<30000;z+=37){int y=0,m=0,d=0;FPCivilFromDays(z,y,m,d);ok=ok && FPDaysFromCivil(y,m,d)==z;}CHECK(ok);}
   CHECK(FPNthSunday(2026,3,2)==8 && FPNthSunday(2026,11,1)==1 && FPLastSunday(2026,3)==29 && FPLastSunday(2026,10)==25);
   CHECK(!FPNYDst(NY(2026,3,8,1,59)) && FPNYDst(NY(2026,3,8,3,0)) && FPNYDst(NY(2026,11,1,1,0)) && !FPNYDst(NY(2026,11,1,2,30)));
   CHECK(!FPEUDst(NY(2026,3,29,0,59)) && FPEUDst(NY(2026,3,29,1,0)) && !FPEUDst(NY(2026,10,25,1,0)));
   // NY+7 brokers keep New York 02:00 at server 09:00 all year.
   CHECK(FPNYToServer(NY(2026,1,15,2,0),1,2)==NY(2026,1,15,9,0) && FPNYToServer(NY(2026,7,15,2,0),1,2)==NY(2026,7,15,9,0));
   // GMT+2 with EU DST: 09:00 in winter and summer, 08:00 in the US/EU mismatch week.
   CHECK(FPNYToServer(NY(2026,1,15,2,0),3,2)==NY(2026,1,15,9,0));
   CHECK(FPNYToServer(NY(2026,3,10,2,0),3,2)==NY(2026,3,10,8,0));
   CHECK(FPNYToServer(NY(2026,7,15,2,0),3,2)==NY(2026,7,15,9,0));
   CHECK(FPNYToServer(NY(2026,7,15,9,30),2,0)==NY(2026,7,15,13,30));
   CHECK(FPServerToNY(NY(2026,3,10,8,0),3,2)==NY(2026,3,10,2,0) && FPServerToNY(NY(2026,7,15,9,0),1,2)==NY(2026,7,15,2,0));
   // Trading days roll at 17:00 New York; evening zones open on the previous calendar day.
   CHECK(FPTradingDay(NY(2026,11,16,16,59))==FPDaysFromCivil(2026,11,16) && FPTradingDay(NY(2026,11,16,17,0))==d17);
   CHECK(FPZoneNYStart(d17,1140)==NY(2026,11,16,19,0) && FPZoneNYEnd(NY(2026,11,16,19,0),1140,240)==NY(2026,11,17,4,0));
   CHECK(FPZoneNYStart(d17,1020)==NY(2026,11,16,17,0) && FPZoneNYStart(d17,0)==NY(2026,11,17,0,0));
   CHECK(FPZoneNYEnd(NY(2026,11,16,20,0),1200,0)==NY(2026,11,17,0,0) && FPZoneNYEnd(NY(2026,11,17,9,30),570,570)==NY(2026,11,17,9,30));

   // ---- time entry
   int mins=-1;
   CHECK(FPParseHHMM("9",mins) && mins==540);
   CHECK(FPParseHHMM("09:30",mins) && mins==570 && FPParseHHMM("930",mins) && mins==570 && FPParseHHMM("0930",mins) && mins==570);
   CHECK(FPParseHHMM(" 9.30 ",mins) && mins==570 && FPParseHHMM("9h30",mins) && mins==570 && FPParseHHMM("24:00",mins) && mins==0);
   CHECK(!FPParseHHMM("25:00",mins) && !FPParseHHMM("12:60",mins) && !FPParseHHMM("ab",mins) && !FPParseHHMM("",mins) && !FPParseHHMM("1:5",mins));
   CHECK(FPHHMM(570)=="09:30" && FPHHMM(0)=="00:00" && FPDuration(9*60)=="9 min" && FPDuration(66*60)=="1h 06m");

   // ---- default list: the seven sessions, the lecture's zones, sorted by trading-day time
   FPZoneConfig cfg;FPZoneDefaults(cfg,false);
   CHECK(cfg.count==33);
   string sessions[]={"Asian","London","New York","London AM","London PM","New York AM","New York PM"};
   {bool ok=true;for(int i=0;i<7;i++){int z=FindZone(cfg,sessions[i]);ok=ok && z>=0 && cfg.zones[z].group==0 && cfg.zones[z].enabled;}CHECK(ok);}
   CHECK(cfg.zones[FindZone(cfg,"London AM")].start==180 && cfg.zones[FindZone(cfg,"New York PM")].end==1020);
   CHECK(cfg.zones[FindZone(cfg,"Macro 09:50")].start==590 && cfg.zones[FindZone(cfg,"Macro 09:50")].end==610 && cfg.zones[FindZone(cfg,"Macro 02:33")].start==153);
   CHECK(!cfg.group_on[2] && cfg.zones[FindZone(cfg,"Midnight Open")].open_line==2 && cfg.zones[FindZone(cfg,"Asian KZ")].extend);
   FPZoneConfig idx_cfg;FPZoneDefaults(idx_cfg,true);
   CHECK(idx_cfg.group_on[2] && idx_cfg.zones[FindZone(idx_cfg,"NY AM KZ (indices)")].enabled && !idx_cfg.zones[FindZone(idx_cfg,"NY KZ")].enabled);
   FPZoneConfig sorted=cfg;FPZSortByTime(sorted);
   CHECK(sorted.zones[0].start>=1020 && sorted.zones[sorted.count-1].start<1020); // evening zones open the trading day

   // ---- settings file round trip and validation
   FPZoneConfig c2=cfg;c2.zones[3].stack=1;c2.zones[5].midline=true;
   CHECK(FPZWriteFile("t2.zones",c2));
   {FPZoneConfig r;CHECK(FPZReadFile("t2.zones",r) && r.zones[3].stack==1 && r.zones[5].midline && r.zones[4].stack==0 && !r.zones[4].midline);}
   // A file written by 1.62 (schema 1): no stack field, midline implied by the range box,
   // and edge markers that ignored their distance.
   {
    int f=FileOpen("old.zones",FILE_WRITE|FILE_BIN,'\t',0);
    FileWriteInteger(f,FPZ_MAGIC,4);FileWriteInteger(f,1,4);FileWriteInteger(f,1|2|4|32|64|128|256|512|1024,4);
    for(int g=0;g<FPZ_GROUPS;g++)FileWriteInteger(f,1|(11<<1),4);
    int head[]={10,62,0,2,0,8,11,0,2};for(int k=0;k<9;k++)FileWriteInteger(f,head[k],4);
    for(int z=0;z<2;z++)
      {
       WText(f,z==0?"Old KZ":"Old session");
       int v[]={120,300,2,1,(int)clrDodgerBlue,1,z==0?4:2,0,6,16,45,1,0};for(int k=0;k<13;k++)FileWriteInteger(f,v[k],4);
       FileWriteInteger(f,1|4,4);   // enabled + box
      }
    FileWriteInteger(f,FPZ_END,4);FileClose(f);
    FPZoneConfig old;CHECK(FPZReadFile("old.zones",old) && old.count==2);
    CHECK(old.zones[0].midline && old.zones[0].stack==0 && old.zones[0].distance==0);   // top-edge marker: distance reset
    CHECK(old.zones[1].midline && old.zones[1].distance==6);                            // above-high marker keeps its gap
    CHECK(old.cut==1 && old.fib_lower==0);                                              // no bits: Half, Full
   }
   {FPZoneConfig d;FPZoneDefaults(d,false);CHECK(d.cut==1 && d.fib_lower==0 && FPZ_SCHEMA==2);
    for(int cut=0;cut<3;cut++)for(int fl=0;fl<3;fl++)
      {
       d.cut=cut;d.fib_lower=fl;CHECK(FPZWriteFile("cut.zones",d));
       FPZoneConfig r;CHECK(FPZReadFile("cut.zones",r) && r.cut==cut && r.fib_lower==fl && r.alert_push==d.alert_push && r.hover==d.hover);
       // Earlier versions read flags bits 0-10 only; the defaults leave the new bits at 0,
       // exactly as 1.63 writes them.
       int flags=(int)((uchar)g_disk["cut.zones"][8]|((uchar)g_disk["cut.zones"][9]<<8)|((uchar)g_disk["cut.zones"][10]<<16)|((uchar)g_disk["cut.zones"][11]<<24));
       CHECK((flags&2047)==((d.enabled?1:0)|(d.upcoming?2:0)|(d.fill?4:0)|(d.gradient?8:0)|(d.fade_old?16:0)|(d.lines_full?32:0)|(d.declutter?64:0)|(d.highlight?128:0)|(d.hover?256:0)|(d.alert_sound?512:0)|(d.alert_push?1024:0)));
       if(cut==1 && fl==0)CHECK((flags>>11)==0);
      }
   }
   CHECK(FPZWriteFile("t.zones",cfg));
   FPZoneConfig back;CHECK(FPZReadFile("t.zones",back));
   {bool ok=back.count==cfg.count && back.days_back==cfg.days_back && back.alert_push==cfg.alert_push && back.group_tf[3]==cfg.group_tf[3];
    for(int i=0;i<cfg.count && ok;i++)ok=back.zones[i].name==cfg.zones[i].name && back.zones[i].start==cfg.zones[i].start && back.zones[i].end==cfg.zones[i].end
       && back.zones[i].ink==cfg.zones[i].ink && back.zones[i].marker==cfg.zones[i].marker && back.zones[i].extend==cfg.zones[i].extend && back.zones[i].open_line==cfg.zones[i].open_line;
    CHECK(ok);}
   g_disk["t.zones"][12]^=0x7F;CHECK(!FPZReadFile("t.zones",back));   // corrupted flags/limits are rejected

   // ---- occurrences: last N trading days, weekends skipped, upcoming only for today
   g_zact=cfg;g_zact.broker_mode=1;g_zact.days_back=3;ZoneResolveBroker();
   CHECK(g_zmode==1);
   g_test_now=(datetime)FPNYToServer(NY(2026,11,16,10,15),1,2);           // Monday 10:15 New York
   ZonesBuild();
   int asian=FindZone(g_zact,"Asian"),pm=FindZone(g_zact,"NY PM KZ");
   {int days=0,pmn=0;bool weekend=false;
    for(int i=0;i<g_zocc_n;i++){if(g_zocc[i].zone==asian)days++;if(g_zocc[i].zone==pm)pmn++;int dw=FPDow(g_zocc[i].day);if(dw==0 || dw==6)weekend=true;}
    CHECK(days==1 && pmn==1 && !weekend);}
   {int i=-1;for(int k=0;k<g_zocc_n;k++)if(g_zocc[k].zone==asian)i=k;
    CHECK(i>=0 && g_zocc[i].ts==(datetime)NY(2026,11,16,2,0) && g_zocc[i].te==(datetime)NY(2026,11,16,11,0));} // Sunday 19:00 NY = Monday 02:00 server
   g_zact.upcoming=false;ZonesBuild();
   {int pmn=0;for(int i=0;i<g_zocc_n;i++)if(g_zocc[i].zone==pm)pmn++;CHECK(pmn==0);}
   g_zact.upcoming=true;g_test_now=(datetime)FPNYToServer(NY(2026,11,17,10,15),1,2);ZonesBuild();
   {int pmn=0,fut=0;for(int i=0;i<g_zocc_n;i++)if(g_zocc[i].zone==pm){pmn++;if(g_zocc[i].future)fut++;}CHECK(pmn==2 && fut==1);}

   // ---- M1 data: exact high/low/open, holidays, liquidity sweeps
   MakeBars(FPNYToServer(NY(2026,11,16,0,0),1,2),(long)g_test_now);
   int lk=FindZone(g_zact,"London KZ");
   {int i=-1;for(int k=0;k<g_zocc_n;k++)if(g_zocc[k].zone==lk && g_zocc[k].day==(int)d17)i=k;
    CHECK(i>=0 && ZoneData(i,g_test_now) && g_zocc[i].state==1);
    double hi=-1,lo=9;for(auto& b:g_bars)if(b.time>=g_zocc[i].ts && b.time<g_zocc[i].te){hi=std::max(hi,b.high);lo=std::min(lo,b.low);}
    CHECK(std::fabs(g_zocc[i].hi-hi)<1e-12 && std::fabs(g_zocc[i].lo-lo)<1e-12 && !ZoneData(i,g_test_now));
    // A spike above the London high after the zone ends is detected as the high being taken.
    MqlRates spike{};spike.time=g_zocc[i].te+30*60;spike.open=hi;spike.high=hi+0.01;spike.low=lo+0.0001;spike.close=hi;
    for(auto& b:g_bars)if(b.time==spike.time)b=spike;
    g_zocc[i].scan_to=0;CHECK(ZoneExtend(i,g_test_now) && g_zocc[i].hi_taken==spike.time);}
   {int i=g_zocc_n++;ArrayResize(g_zocc,g_zocc_n);g_zocc[i]=g_zocc[0];g_zocc[i].ts=(datetime)NY(2026,10,1,9,0);g_zocc[i].te=g_zocc[i].ts+3600;g_zocc[i].state=0;
    CHECK(!ZoneData(i,g_test_now) && g_zocc[i].state==2);g_zocc_n--;}   // no bars long ago: treated as a holiday

   // ---- live state and the Zones button
   ZoneLiveState(g_test_now);
   CHECK(g_zlive_on && g_zlive_ink==clrOrange);                          // London Close KZ is the shortest live zone at 10:15
   CHECK(g_zbutton_tip.find("Live: London Close KZ")!=string::npos && g_zbutton_tip.find("Next: Macro 10:50 in 35 min")!=string::npos);
   CHECK(g_zbutton_tip.find("New York 10:15")!=string::npos);

   // ---- alerts: once per zone and day across charts, within the start minute
   int nyk=FindZone(g_zact,"NY Lunch");g_zact.zones[nyk].alert=true;
   g_test_now=(datetime)FPNYToServer(NY(2026,11,17,12,0),1,2)+20;
   ZoneAlerts(g_test_now);CHECK(g_sounds==1 && g_pushes==1);
   ZoneAlerts(g_test_now+30);CHECK(g_sounds==1);                          // another chart: already claimed
   ZoneAlerts(g_test_now+300);CHECK(g_sounds==1);                         // outside the window
   g_zact.alert_lead=5;g_test_now=(datetime)FPNYToServer(NY(2026,11,17,13,25),1,2);
   int pmk=FindZone(g_zact,"NY PM KZ");g_zact.zones[pmk].alert=true;
   ZoneAlerts(g_test_now);CHECK(g_sounds==2 && g_pushes==2);g_zact.alert_lead=0;

   // ---- compositing: translucent layers blend instead of overwriting
   {MQLArr<FPLayer> layers;layers.v.resize(2);
    FPLayerSet(layers[0],0,9,0,9,(color)0xFF0000,(color)0xFF0000,.5,.5,0);     // blue
    FPLayerSet(layers[1],5,14,0,9,(color)0x0000FF,(color)0x0000FF,.5,.5,0);    // red on top
    MQLArr<FPSeg> segs;int n=FPComposeSegments(layers,2,100,100,segs);
    CHECK(n==3 && segs[1].x0==5 && segs[1].x1==9 && segs[1].argb==0xBFAA0055 && segs[0].argb==0x800000FF && segs[2].argb==0x80FF0000);
    CHECK(segs[0].argb1==segs[0].argb && segs[1].argb1==segs[1].argb);        // flat cells
    layers[0].ink=0x0000FF;layers[0].ink2=0x0000FF;layers[1].ink=0xFF0000;layers[1].ink2=0xFF0000;   // red under blue: order matters
    n=FPComposeSegments(layers,2,100,100,segs);CHECK(n==3 && segs[1].argb==0xBF5500AA);
    // A Fib fill (kind 1) under zone shading (kind 0): the cut removes part of the Fib's
    // opacity inside the zone only.
    FPLayerSet(layers[0],0,9,0,9,(color)0xFF0000,(color)0xFF0000,.5,.5,1);     // blue Fib
    FPLayerSet(layers[1],5,14,0,9,(color)0x0000FF,(color)0x0000FF,.5,.5,0);    // red zone on top
    n=FPComposeSegments(layers,2,100,100,segs,0.0);CHECK(n==3 && segs[1].argb==0xBFAA0055);
    n=FPComposeSegments(layers,2,100,100,segs,0.5);CHECK(n==3 && segs[1].argb==0x9FCC0033 && segs[0].argb==0x800000FF);
    n=FPComposeSegments(layers,2,100,100,segs,1.0);CHECK(n==3 && segs[1].argb==0x80FF0000 && segs[0].argb==0x800000FF);
    // A colour gradient: the cell keeps its top and bottom colours, drawn row by row.
    FPLayerSet(layers[0],0,9,0,10,(color)0x0000FF,(color)0xFF0000,1,1,1);     // red at the top, blue at the bottom
    n=FPComposeSegments(layers,1,100,100,segs);CHECK(n==1 && segs[0].argb==0xFFFF0000 && segs[0].argb1==0xFF0000FF);
    CHECK(FPLerpARGB(0xFFFF0000,0xFF0000FF,0.5)==0xFF800080);
    g_rects.clear();g_rec=true;DrawLayers(g_fill_canvas,layers,1,100,100);g_rec=false;
    CHECK(g_rects.size()==11 && FillAt(3,0)==0xFFFF0000 && FillAt(3,10)==0xFF0000FF && FillAt(3,5)==0xFF800080);
    // At low opacity a tall gradient needs few bands, and every band stays within one
    // visible step of the exact row colour.
    FPLayerSet(layers[0],0,9,0,599,(color)0x0000FF,(color)0xFF0000,.12,.12,1);
    g_rects.clear();g_rec=true;DrawLayers(g_fill_canvas,layers,1,100,1000);g_rec=false;
    {bool ok=g_rects.size()<=40;
     for(int y=0;y<600 && ok;y+=7)
       {
        uint got=FillAt(3,y),want=RefARGB(FPBlend((color)0x0000FF,(color)0xFF0000,y/599.0),31);
        ok=((got>>24)==31);
        for(int sh=0;sh<=16 && ok;sh+=8)ok=std::abs((int)((got>>sh)&255)-(int)((want>>sh)&255))*31/255<=1;
       }
     CHECK(ok);}
    // A zone's opacity gradient: few bands, each one step of opacity or less from the next.
    FPLayerSet(layers[0],0,9,0,1079,(color)0x00AAFF,(color)0x00AAFF,.08,.012,0);
    g_rects.clear();g_rec=true;DrawLayers(g_fill_canvas,layers,1,100,1080);g_rec=false;
    {bool ok=g_rects.size()>=10 && g_rects.size()<=30 && (FillAt(3,0)>>24)>=19 && (FillAt(3,1079)>>24)<=4;
     for(int y=1;y<1080 && ok;y++)ok=std::abs((int)(FillAt(3,y)>>24)-(int)(FillAt(3,y-1)>>24))<=1;
     CHECK(ok);}
    }

   // ---- marker strips: every zone has its own rectangle; overlaps step apart; placement honoured
   FPZoneDefaults(g_zact,false);g_height=600;g_width=1600;
   g_zocc_n=0;g_zvis_n=0;ArrayResize(g_zocc,16);ArrayResize(g_zvis,16);
   auto add=[&](const string& name,int s0,int s1)
     {int z=FindZone(g_zact,name),i=g_zocc_n++,v=g_zvis_n++;g_zocc[i].zone=z;g_zocc[i].ts=(datetime)((1000+s0)*60);g_zocc[i].te=(datetime)((1000+s1)*60);
      g_zocc[i].state=1;g_zocc[i].live=false;g_zocc[i].future=false;g_zocc[i].age=0;
      g_zvis[v].occ=i;g_zvis[v].x0=400+s0;g_zvis[v].x1=400+s1;g_zvis[v].yh=100;g_zvis[v].yl=300;g_zvis[v].yo=FP_OFF;};
   add("Asian",-300,240);add("London",180,720);add("New York",480,1020);add("London AM",180,420);
   add("London PM",420,720);add("New York AM",480,720);add("New York PM",720,1020);
   auto overlap=[&](int p,int q){return !(g_zmark[p].x0>g_zmark[q].x1 || g_zmark[q].x0>g_zmark[p].x1) && g_zmark[p].y0<g_zmark[q].y1 && g_zmark[q].y0<g_zmark[p].y1;};
   auto check_sep=[&](int anchor,int dist)
     {
      for(int z=0;z<7;z++){g_zact.zones[z].marker=anchor;g_zact.zones[z].distance=dist;g_zact.zones[z].stack=0;g_zact.zones[z].height=15;}
      ZonesLayout();
      bool ok=g_zmark_n==7;
      for(int p=0;p<g_zmark_n;p++)
        {
         ok=ok && g_zmark[p].y1-g_zmark[p].y0==16;                       // its own height: nothing wraps it
         for(int q=p+1;q<g_zmark_n;q++)ok=ok && !overlap(p,q);           // never shares a rectangle
        }
      // The first strip placed (longest, earliest: Asian) sits exactly at its distance;
      // London overlaps it and steps one row away; touching AM/PM strips share a row.
      int A=MarkOfZone(FindZone(g_zact,"Asian")),L=MarkOfZone(FindZone(g_zact,"London"));
      int LA=MarkOfZone(FindZone(g_zact,"London AM")),LP=MarkOfZone(FindZone(g_zact,"London PM"));
      int expect=anchor==1?300+dist:(anchor==2?100-dist-16:(anchor==3?g_height-dist-16:dist));
      int step=(anchor==1 || anchor==4)?18:-18;
      ok=ok && g_zmark[A].y0==expect && g_zmark[L].y0==expect+step && g_zmark[LA].y0==g_zmark[LP].y0;
      return ok;
     };
   CHECK(check_sep(3,0));CHECK(check_sep(4,0));CHECK(check_sep(1,6));CHECK(check_sep(2,6));CHECK(check_sep(3,10));
   // A fixed strip stays exactly where its distance puts it; automatic ones keep clear of it.
   {int lz=FindZone(g_zact,"London");g_zact.zones[lz].stack=1;g_zact.zones[lz].distance=40;
    for(int z=0;z<7;z++)if(z!=lz){g_zact.zones[z].marker=3;g_zact.zones[z].distance=0;g_zact.zones[z].stack=0;}
    g_zact.zones[lz].marker=3;ZonesLayout();
    int L=MarkOfZone(lz);bool ok=g_zmark[L].y0==g_height-40-16;
    for(int q=0;q<g_zmark_n;q++)if(q!=L)ok=ok && !overlap(q,L);
    CHECK(ok);g_zact.zones[lz].stack=0;}
   // Sharing even one pixel column is an overlap: London PM moved onto London AM's last column.
   {int la=FindZone(g_zact,"London AM"),lp=FindZone(g_zact,"London PM"),vp=-1;
    for(int z=0;z<7;z++){g_zact.zones[z].marker=3;g_zact.zones[z].distance=0;g_zact.zones[z].stack=0;}
    for(int v=0;v<g_zvis_n;v++)if(g_zocc[g_zvis[v].occ].zone==lp)vp=v;
    g_zvis[vp].x0--;ZonesLayout();
    int A=MarkOfZone(la),P=MarkOfZone(lp);CHECK(g_zmark[A].x1==g_zmark[P].x0 && g_zmark[A].y0!=g_zmark[P].y0 && !overlap(A,P));
    g_zvis[vp].x0++;}
   // Two fixed strips both stay exactly at their distance, even on top of each other, and
   // automatic strips keep clear of them even where they would otherwise come first.
   {int lz=FindZone(g_zact,"London"),nz=FindZone(g_zact,"New York");
    for(int z=0;z<7;z++){g_zact.zones[z].marker=3;g_zact.zones[z].distance=0;g_zact.zones[z].stack=0;}
    g_zact.zones[lz].stack=1;g_zact.zones[nz].stack=1;ZonesLayout();
    int L=MarkOfZone(lz),N=MarkOfZone(nz);bool ok=g_zmark[L].y0==g_height-16 && g_zmark[N].y0==g_height-16;
    for(int q=0;q<g_zmark_n;q++)if(q!=L && q!=N)ok=ok && !overlap(q,L) && !overlap(q,N);
    CHECK(ok);g_zact.zones[lz].stack=0;g_zact.zones[nz].stack=0;}

   // ---- end-to-end render smoke test (AddressSanitizer build)
   FPZoneDefaults(g_zcfg,false);g_zcfg.broker_mode=1;g_zcfg.zones[FindZone(g_zcfg,"Asian KZ")].extend=true;
   g_zact=g_zcfg;g_zocc_dirty=true;g_tf=4;g_view_scale=2;g_view_max=1.2;g_cull_ok=false;
   g_test_now=(datetime)FPNYToServer(NY(2026,11,17,10,15),1,2);
   MakeBars(FPNYToServer(NY(2026,11,14,0,0),1,2),(long)g_test_now);
   g_xy_t0=FPNYToServer(NY(2026,11,16,18,0),1,2);
   g_owner=true;for(int f=0;f<30;f++){g_dirty=true;Render();}
   CHECK(g_zvis_n>0 && g_zmark_n>0 && g_zfill_n>0 && g_zfill_sig!=0);
   {int k=MarkOfZone(FindZone(g_zact,"London"));CHECK(k>=0);
    int occ=-1,kind=-1;CHECK(FindZoneAt((g_zmark[k].x0+g_zmark[k].x1)/2,(g_zmark[k].y0+g_zmark[k].y1)/2,occ,kind) && kind==0 && g_zocc[occ].zone==FindZone(g_zact,"London"));
    MQLArr<string> lines;color accent=clrNONE;ZoneTip(occ,kind,lines,accent);
    CHECK(ArraySize(lines)>=6 && lines[0]=="London" && lines[2]=="New York\t03:00 - 12:00" && accent==g_zact.zones[FindZone(g_zact,"London")].ink);}
   // Hovering the Asian KZ midline and its extended high gives line tooltips. Make the data
   // unambiguous first: Monday's high untaken for 3 hours, the Midnight Open a little lower.
   {int az=FindZone(g_zact,"Asian KZ"),mo=FindZone(g_zact,"Midnight Open"),v=-1;
    for(int i=0;i<g_zocc_n;i++)
      {
       if(g_zocc[i].zone==az && g_zocc[i].day==(int)d17)
         {g_zocc[i].hi_taken=g_zocc[i].te+3*3600;g_zocc[i].lo_taken=0;g_zocc[i].hi=1.1150;g_zocc[i].lo=1.0950;}  // 60 px tall, low untaken
       if(g_zocc[i].zone==mo && g_zocc[i].day==(int)d17)g_zocc[i].op-=0.002;
      }
    g_dirty=true;Render();
    for(int q=0;q<g_zvis_n;q++){int i=g_zvis[q].occ;if(g_zocc[i].zone==az && g_zocc[i].day==(int)d17 && g_zvis[q].yh!=FP_OFF)v=q;}
    CHECK(v>=0);
    if(v>=0)
      {
       int i=g_zvis[v].occ,occ=-1,kind=-1,ym=(g_zvis[v].yh+g_zvis[v].yl)/2;MQLArr<string> lines;color accent=clrNONE;
       CHECK(FindZoneAt((g_zvis[v].x0+g_zvis[v].x1)/2,ym,occ,kind) && occ==i && kind==3);
       ZoneTip(occ,kind,lines,accent);
       CHECK(lines[1]=="50% of the range (midline)" && lines[2]=="Price	"+DoubleToString((g_zocc[i].hi+g_zocc[i].lo)/2,_Digits));
       CHECK(g_zvis[v].xh==g_zvis[v].x1+180);                                   // extended to the taken time
       CHECK(FindZoneAt(g_zvis[v].x1+60,g_zvis[v].yh,occ,kind) && occ==i && kind==5);
       ZoneTip(occ,kind,lines,accent);
       bool status=false;for(int q=0;q<ArraySize(lines);q++)if(lines[q]=="Status\tTaken 03:00 New York, Tue")status=true;
       CHECK(lines[1]=="Range high, extended" && status && lines[2]=="Price\t"+DoubleToString(g_zocc[i].hi,_Digits));
       CHECK(!FindZoneAt(g_zvis[v].x1+240,g_zvis[v].yh,occ,kind) || kind!=5);       // beyond the sweep: no longer this line
       CHECK(FindZoneAt(g_zvis[v].x0+3,g_zvis[v].yl,occ,kind) && kind==2);        // range box edge
       // The untaken low runs on to the right edge, past the swept high.
       CHECK(g_zvis[v].xl==g_width-1);
       CHECK(FindZoneAt(g_zvis[v].x1+240,g_zvis[v].yl,occ,kind) && occ==i && kind==6);
       ZoneTip(occ,kind,lines,accent);
       bool open=false;for(int q=0;q<ArraySize(lines);q++)if(lines[q]=="Status\tNot taken yet")open=true;
       CHECK(lines[1]=="Range low, extended" && open && lines[2]=="Price\t"+DoubleToString(g_zocc[i].lo,_Digits));
       // A line answers within 3 px, not further.
       int xm=(g_zvis[v].x0+g_zvis[v].x1)/2;
       CHECK(FindZoneAt(xm,ym+3,occ,kind) && occ==i && kind==3);
       CHECK(!FindZoneAt(xm,ym+8,occ,kind) || kind!=3);
       // The 50% line has its own switch: drawn and hoverable without the box, gone without the switch.
       g_zact.zones[az].box=false;g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
       int on_rows=RowPieces(ym,g_zvis[v].x0+1,g_zvis[v].x1-1);
       CHECK(g_zvis[v].occ==i && FindZoneAt(xm,ym,occ,kind) && occ==i && kind==3);
       g_zact.zones[az].box=true;g_zact.zones[az].midline=false;g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
       int off_rows=RowPieces(ym,g_zvis[v].x0+1,g_zvis[v].x1-1);
       CHECK(on_rows>off_rows);
       CHECK(g_zvis[v].occ==i && (!FindZoneAt(xm,ym,occ,kind) || kind!=3));
       g_zact.zones[az].midline=true;g_dirty=true;Render();
      }
    int w=-1;
    for(int q=0;q<g_zvis_n;q++){int i=g_zvis[q].occ;if(g_zocc[i].zone==mo && g_zocc[i].day==(int)d17 && g_zvis[q].yo!=FP_OFF)w=q;}
    CHECK(w>=0);
    if(w>=0){int occ=-1,kind=-1;CHECK(FindZoneAt(g_zvis[w].x0+40,g_zvis[w].yo,occ,kind) && kind==4);}}
   for(int i=0;i<200;i++){g_zmark_n=0;Render();}                       // repeated frames stay stable
   CHECK(g_zmark_n>0);

   // ---- shading (1.64): Fib and zone fills blend in one pass, zones on top
   {
    auto fibrect=[&](int slot,ENUM_TIMEFRAMES tf,color ink,int opacity,long x0,long x1,double p0,double p1)
      {
       FPSetup &s=g_sets[slot];MakeFib(s,900+slot,"Shade",false,tf);
       s.ta=(datetime)(g_xy_t0+x0*60);s.tb=(datetime)(g_xy_t0+x1*60);s.left=s.ta;s.right=s.tb;s.pa=p0;s.pb=p1;
       s.fill=true;s.fill_rays=false;s.gradient=false;s.fill_top=ink;s.fill_bottom=ink;s.opacity=opacity;
      };
    auto shade=[&](){g_rects.clear();g_rec=true;g_fill_sig=0;g_dirty=true;Render();g_rec=false;};
    g_selected=-1;g_editor=false;
    // A red H4 range over the London KZ column (x 478-657); y 270-330.
    fibrect(0,PERIOD_H4,(color)0x0000FF,30,240,840,1.11,1.09);g_count=1;
    g_zact.cut=0;shade();
    uint fib=FillAt(420,300),zone=FillAt(560,100),both=FillAt(560,300);
    CHECK(fib!=0 && zone!=0 && both!=0 && fib!=both);
    CHECK(Near(both,RefOver(fib,zone)));                                   // the killzone blends over the range
    g_zact.cut=2;shade();CHECK(FillAt(560,300)==zone && FillAt(420,300)==fib); // Clear: no Fib shading inside zones
    g_zact.cut=1;shade();{uint half=FillAt(560,300);CHECK((half>>24)>(zone>>24) && (half>>24)<(both>>24));}
    // Changing a setting alone redraws the shading (no forced redraw here).
    auto frame=[&](){g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;};
    g_zact.cut=2;frame();CHECK(FillAt(560,300)==zone);
    g_zact.fib_lower=2;frame();CHECK(FillAt(420,300)==0);
    g_sets[0].source_tf=PERIOD_M5;frame();CHECK(FillAt(420,300)==fib);          // its own timeframe changes the outcome
    g_sets[0].source_tf=PERIOD_H4;g_zact.fib_lower=0;g_zact.cut=1;
    // Order: the weekly range underneath, the H4 range on top, whatever the list order.
    g_zact.enabled=false;g_zact.cut=1;
    fibrect(1,PERIOD_W1,(color)0xFF0000,30,600,1100,1.10,1.08);g_count=2;  // blue weekly, y 300-360
    shade();
    uint red=FillAt(420,300),blue=FillAt(1000,350),mix=FillAt(700,320);
    CHECK(red!=0 && blue!=0 && Near(mix,RefOver(blue,red)) && !Near(mix,RefOver(red,blue)));
    // Same timeframe: list order, the selected Fib on top.
    g_sets[1].source_tf=PERIOD_H4;shade();CHECK(Near(FillAt(700,320),RefOver(red,blue)));
    g_selected=0;shade();CHECK(Near(FillAt(700,320),RefOver(blue,red)));g_selected=-1;
    // Below a Fib's own timeframe (this chart is M5): Full, Faint (a third) or Off.
    g_count=1;fibrect(0,PERIOD_H4,(color)0x0000FF,60,240,840,1.11,1.09);
    g_zact.fib_lower=0;shade();CHECK((FillAt(420,300)>>24)==153);
    CHECK(FibShadeFactor(g_sets[0])==1.0);
    g_zact.fib_lower=1;shade();CHECK((FillAt(420,300)>>24)==51);
    g_zact.fib_lower=2;shade();CHECK(FillAt(420,300)==0);
    g_sets[0].source_tf=PERIOD_M5;shade();CHECK((FillAt(420,300)>>24)==153); // drawn on this timeframe: as set
    g_sets[0].source_tf=PERIOD_M1;shade();CHECK((FillAt(420,300)>>24)==153); // drawn on a lower one: as set
    g_zact.fib_lower=0;
    // A gradient fill keeps its exact colour on every row.
    fibrect(0,PERIOD_H4,(color)0x0000FF,100,240,840,1.11,1.09);g_sets[0].gradient=true;g_sets[0].fill_bottom=(color)0xFF0000;
    shade();
    for(int y=270;y<=330;y+=10)CHECK(Near(FillAt(420,y),RefARGB(FPBlend((color)0x0000FF,(color)0xFF0000,(y-270)/60.0),255),1));
    // A range running off the top of the chart keeps its gradient anchored to its real top.
    fibrect(0,PERIOD_H4,(color)0x0000FF,100,240,840,1.25,1.09);g_sets[0].gradient=true;g_sets[0].fill_bottom=(color)0xFF0000;   // y -150..330
    shade();
    CHECK(Near(FillAt(420,0),RefARGB(FPBlend((color)0x0000FF,(color)0xFF0000,150/480.0),255),1));
    fibrect(0,PERIOD_H4,(color)0x0000FF,100,240,840,1.11,1.09);g_sets[0].gradient=true;g_sets[0].fill_bottom=(color)0xFF0000;
    // ... and still does under a zone, where the zone blends on top.
    g_zact.enabled=true;g_zact.cut=0;shade();
    CHECK(Near(FillAt(560,280),RefOver(RefARGB(FPBlend((color)0x0000FF,(color)0xFF0000,10/60.0),255),FillAt(560,100))));
    g_count=0;g_zact=g_zcfg;g_dirty=true;Render();
   }

   // ---- Zones window: tabs, table edits, popups, palette, presets, apply
   g_zstore="mem.zones";SaveZones();CHECK(FileIsExist("mem.zones",0));
   OpenZones();CHECK(g_zeditor && g_zedit.count==33);
   {g_dirty=true;Render();int lz=FindZone(g_zedit,"London"),k=MarkOfZone(lz);CHECK(k>=0);
    int cx=(g_zmark[k].x0+g_zmark[k].x1)/2,cy=(g_zmark[k].y0+g_zmark[k].y1)/2,old=g_zedit.zones[lz].distance;
    int gap=g_height-g_zmark[k].y1;                                       // where it is now (after auto stacking)
    CHECK(ZoneDragBegin(cx,cy) && g_zdrag);
    ZoneDragMove(cx,cy-30);CHECK(g_zedit.zones[lz].distance==gap+30 && g_zedit.zones[lz].stack==1 && g_zact.zones[lz].distance==gap+30);
    ZoneDragEnd();CHECK(!g_zdrag);
    g_dirty=true;Render();k=MarkOfZone(lz);CHECK(g_zmark[k].y1==g_height-(gap+30));        // drawn exactly where it was dropped
    CHECK(ZoneDragBegin((g_zmark[k].x0+g_zmark[k].x1)/2,(g_zmark[k].y0+g_zmark[k].y1)/2));
    ZoneDragMove(cx,cy-80);CancelDrag();CHECK(!g_zdrag && g_zedit.zones[lz].distance==gap+30); // Esc restores
    g_zedit.zones[lz].distance=old;g_zedit.zones[lz].stack=0;ZonePreview(false);
    CloseZones();CHECK(!ZoneDragBegin(cx,cy));OpenZones();}                                    // only while the window is open
   {int lz=FindZone(g_zedit,"London");
    int om=g_zedit.zones[lz].marker,od=g_zedit.zones[lz].distance,os=g_zedit.zones[lz].stack;
    for(int a=1;a<=4;a++)
      {
       g_zedit.zones[lz].marker=a;g_zedit.zones[lz].distance=10;g_zedit.zones[lz].stack=1;ZonePreview(false);
       g_dirty=true;Render();
       int k=-1;for(int q=0;q<g_zmark_n;q++)if(g_zocc[g_zvis[g_zmark[q].vis].occ].zone==lz && g_zmark[q].anchor==a && g_zmark[q].x0>=0)k=q;
       CHECK(k>=0);if(k<0)continue;
       int occ=g_zvis[g_zmark[k].vis].occ,cx=(g_zmark[k].x0+g_zmark[k].x1)/2,cy=(g_zmark[k].y0+g_zmark[k].y1)/2,y0=g_zmark[k].y0;
       int away=(a==1 || a==4)?20:-20;                                      // further from price / the edge
       CHECK(ZoneDragBegin(cx,cy));ZoneDragMove(cx,cy+away);ZoneDragEnd();
       CHECK(g_zedit.zones[lz].distance==30 && g_zedit.zones[lz].stack==1);
       g_dirty=true;Render();
       int k2=-1;for(int q=0;q<g_zmark_n;q++)if(g_zvis[g_zmark[q].vis].occ==occ)k2=q;
       CHECK(k2>=0 && g_zmark[k2].y0==y0+away);
      }
    g_zedit.zones[lz].marker=3;g_zedit.zones[lz].distance=0;g_zedit.zones[lz].stack=0;ZonePreview(false);
    g_dirty=true;Render();int k=MarkOfZone(lz);CHECK(k>=0);
    int cx=(g_zmark[k].x0+g_zmark[k].x1)/2,cy=(g_zmark[k].y0+g_zmark[k].y1)/2;
    CHECK(ZoneDragBegin(cx,cy));ZoneDragMove(cx,cy-2);ZoneDragEnd();                        // a plain click changes nothing
    CHECK(!g_zdrag && g_zedit.zones[lz].distance==0 && g_zedit.zones[lz].stack==0);
    CHECK(ZoneDragBegin(cx,cy));ZoneDragMove(cx,cy-50);CHECK(g_zedit.zones[lz].stack==1 && g_zedit.zones[lz].distance>0);
    CancelDrag();CHECK(!g_zdrag && g_zedit.zones[lz].distance==0 && g_zedit.zones[lz].stack==0 && g_zact.zones[lz].stack==0);
    // The Esc key during a drag undoes only the drag: the window stays open with its other edits.
    int ol=g_zedit.zones[lz].label;g_zedit.zones[lz].label=2;ZonePreview(false);
    g_dirty=true;Render();k=MarkOfZone(lz);CHECK(k>=0);
    cx=(g_zmark[k].x0+g_zmark[k].x1)/2;cy=(g_zmark[k].y0+g_zmark[k].y1)/2;
    CHECK(ZoneDragBegin(cx,cy));ZoneDragMove(cx,cy-50);
    {long lp=27;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);}
    CHECK(!g_zdrag && g_zeditor && g_zedit.zones[lz].distance==0 && g_zedit.zones[lz].stack==0 && g_zedit.zones[lz].label==2);
    // Closing the window mid-drag (a hotkey) also ends the drag cleanly.
    CHECK(ZoneDragBegin(cx,cy));ZoneDragMove(cx,cy-50);CloseZones();
    CHECK(!g_zdrag && !g_zeditor && g_zedit.zones[lz].stack==0);OpenZones();
    // Resting on a strip pauses chart scrolling, so a drag starts without panning the chart.
    g_dirty=true;Render();k=MarkOfZone(lz);cx=(g_zmark[k].x0+g_zmark[k].x1)/2;cy=(g_zmark[k].y0+g_zmark[k].y1)/2;
    ReleaseScroll();HandlePointer(cx,cy,false);CHECK(g_scroll_held);
    int ex=-1,ey=-1;
    for(int yy=5;yy<g_height && ex<0;yy+=7)for(int xx=5;xx<g_width && ex<0;xx+=37)if(!HitUI(xx,yy) && FindZoneMarkAt(xx,yy)<0){ex=xx;ey=yy;}
    CHECK(ex>=0);HandlePointer(ex,ey,false);CHECK(!g_scroll_held);
    CloseZones();HandlePointer(cx,cy,false);CHECK(!g_scroll_held);OpenZones();      // not without the window
    g_zedit.zones[lz].label=ol;
    g_zedit.zones[lz].marker=om;g_zedit.zones[lz].distance=od;g_zedit.zones[lz].stack=os;ZonePreview(false);}
   {int keep_rows=g_rows;g_rows=6;g_ztab=2;g_ui_dirty=true;BuildUI();                       // smallest window
    int note=RegFind(UIS("Z.FillNote")),save=RegFind(UIS("Z.Save"));
    CHECK(RegFind(UIS("Z.Cut2"))>=0 && RegFind(UIS("Z.Ftf2"))>=0 && note>=0 && save>=0 && g_reg[note].y+U(16)<=g_reg[save].y);
    g_rows=keep_rows;}
   for(int t=0;t<4;t++){g_ztab=t;g_ui_dirty=true;BuildUI();}
   CHECK(RegFind(UIS("Z.Tab3"))>=0 && RegFind(UIS("Z.Name0"))>=0 && RegFind(UIS("T.Zones"))>=0);
   CHECK(HitUI(g_panel_x+U(400),g_panel_y+U(100)));
   ZonesClick("Flt1");BuildUI();CHECK(g_zfilter==0 && RegFind(UIS("Z.Name7"))<0);   // sessions only
   ZonesClick("Flt0");BuildUI();
   // Typing a new start time and harvesting it.
   ObjectSetString(0,UIS("Z.Start1"),OBJPROP_TEXT,"2:30");CHECK(HarvestZoneEdits() && g_zedit.zones[1].start==150);
   ObjectSetString(0,UIS("Z.Start1"),OBJPROP_TEXT,"99:99");CHECK(!HarvestZoneEdits() && g_zedit.zones[1].start==150);
   ObjectSetString(0,UIS("Z.Start1"),OBJPROP_TEXT,"03:00");HarvestZoneEdits();BuildUI();
   ZoneMarkerPopup(1);CHECK(g_popup==14);ZonePopupClick(Obj("Q.Pos4"));CHECK(g_zedit.zones[1].marker==4);
   ZonePopupClick(Obj("Q.DistUp"));CHECK(g_zedit.zones[1].distance==2);ZonePopupClick(Obj("Q.Done"));CHECK(g_popup==0);
   ZonePopupClick(Obj("Q.St1"));                                         // (popup already closed: ignored)
   ZoneMarkerPopup(1);ZonePopupClick(Obj("Q.St1"));CHECK(g_zedit.zones[1].stack==1);ZonePopupClick(Obj("Q.St0"));CHECK(g_zedit.zones[1].stack==0);ClosePopup();
   ZoneMorePopup(1);ZonePopupClick(Obj("Q.Box"));CHECK(g_zedit.zones[1].box && !g_zedit.zones[1].midline);
   ZonePopupClick(Obj("Q.Mid"));CHECK(g_zedit.zones[1].midline);ZonePopupClick(Obj("Q.Open1"));CHECK(g_zedit.zones[1].open_line==1);ClosePopup();
   Dropdown(10,1);CHECK(g_popup==10 && g_popup_items==6);DropdownChoice(5);ClosePopup();CHECK(g_zedit.zones[1].style==5);
   g_ztab=0;BuildUI();Dropdown(13,-1);CHECK(g_popup==13);DropdownChoice(3);ClosePopup();CHECK(g_zedit.broker_mode==3);
   Palette(-1001);CHECK(g_popup==3);PickApply(clrRed);CHECK(g_zedit.zones[1].ink==clrRed);
   ZonesClick("Add");CHECK(g_zedit.count==34 && g_zedit.zones[33].group==1);
   ZonesClick("Remove33");CHECK(g_zedit.count==33);
   ZonesClick("Grp2");CHECK(g_zedit.group_on[2]);
   ZonesClick("TfDn3");CHECK(g_zedit.group_tf[3]==3);
   ZonesClick("Mode2");CHECK(g_zedit.fill_mode==2);
   ZonesClick("Cut2");CHECK(g_zedit.cut==2 && g_zact.cut==2 && g_zcfg.cut==1);         // live preview, not committed
   ZonesClick("Ftf1");CHECK(g_zedit.fib_lower==1 && g_zact.fib_lower==1);
   CHECK(g_zcfg.zones[1].ink!=clrRed);                                   // nothing committed yet
   PresetBrowser(false);CHECK(g_preset_zones && g_preset_count==2 && g_preset_names[0]==FPZ_BUILTIN_FX);
   ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,FPZ_BUILTIN_IDX);PresetDelete();CHECK(g_preset_count==2 && g_texts[Obj("R.Message")]=="Built-in presets can't be deleted.");
   ClosePopup();
   ZonesClick("Apply");CHECK(g_zcfg.zones[1].ink==clrRed && g_zcfg.broker_mode==3 && g_zeditor);
   FPZoneConfig reread;CHECK(FPZReadFile("mem.zones",reread) && reread.zones[1].ink==clrRed && reread.cut==2 && reread.fib_lower==1);
   g_preset_name=FPZ_BUILTIN_IDX;g_preset_save=false;ZonePresetAction();
   CHECK(g_zedit.zones[FindZone(g_zedit,"NY AM KZ (indices)")].enabled && g_zedit.broker_mode==3); // broker time kept
   CHECK(g_zedit.cut==2 && g_zedit.fib_lower==1);                                       // and the Fib-shading settings
   ZonesClick("Cancel");CHECK(!g_zeditor && g_zact.zones[1].ink==clrRed);
   g_zcfg.enabled=true;ToggleZonesShown();CHECK(!g_zcfg.enabled);ToggleZonesShown();CHECK(g_zcfg.enabled);

   // ---- drawing types (1.65): detection from the two anchors
   auto bars=[](std::vector<std::array<double,4>> v)
     {MQLArr<MqlRates> r;for(size_t i=0;i<v.size();i++){MqlRates m{};m.time=(datetime)(3600000+3600*i);m.open=v[i][0];m.high=v[i][1];m.low=v[i][2];m.close=v[i][3];r.v.push_back(m);}return r;};
   auto kind=[](MQLArr<MqlRates>& c,int ia,double pa,int ib,double pb,int want,int want_dir)
     {int dir=-1;int k=FPDetectKind(c,ia,pa,ib,pb,1e-6,dir);return k==want && dir==want_dir;};
   {
    auto fvg=bars({{100,101.2,99.2,100.8},{100.8,101.5,99.9,100.4},{100.4,102,100.1,101.6},{101.4,106,101.2,105.6},{105.3,107,103.4,106.6}});
    CHECK(kind(fvg,2,102,4,103.4,FPK_FVG,1));
    CHECK(kind(fvg,4,103.4,2,102,FPK_FVG,1));                              // either drawing direction
    CHECK(kind(fvg,2,102.5,4,103.4,FPK_NONE,0));                           // an anchor off the candle's prices
    auto fvgd=bars({{106,106.8,105.6,106.4},{106.4,106.9,105.9,106.1},{106.1,106.4,105,105.3},{105.5,105.7,101.4,101.8},{101.9,103.6,101,101.4}});
    CHECK(kind(fvgd,2,105,4,103.6,FPK_FVG,2));
    auto vi=bars({{100,100.8,99.3,99.6},{99.6,100.5,99,100.2},{100.2,101.9,100,101.6},{102.6,104,101.8,103.7}});
    CHECK(kind(vi,2,101.6,3,102.6,FPK_VI,1));
    CHECK(kind(vi,2,101.6,3,101.8,FPK_NONE,0));                            // body to wick is not an imbalance
    CHECK(kind(vi,2,101.9,3,101.8,FPK_KR,0));                              // a high and a lower low: a (small) key range
    auto uf=bars({{100,100.9,99.4,100.6},{100.6,101,99.8,100.2},{100.2,101.6,99.9,101.3},{101.1,105,100.9,104.6},{105.2,106.4,103,106}});
    CHECK(kind(uf,2,101.6,4,105.2,FPK_UFVG,1));                            // the FVG plus its imbalance
    CHECK(kind(uf,2,101.6,4,103,FPK_FVG,1));                               // just the FVG's own edges
    CHECK(kind(uf,2,101.3,4,105.2,FPK_UFVG,1));                            // body edge to body edge with one imbalance
    auto nogap=bars({{100,100.6,99.4,100.3},{100.3,101.9,100.1,101.2},{101.5,103.4,101.3,103},{102.9,104.2,101.7,103.9}});
    CHECK(kind(nogap,1,101.2,3,102.9,FPK_NONE,0));                         // one imbalance and no FVG: nothing
    auto ufd=bars({{106,106.6,105.5,106.2},{106.2,106.5,105.2,105.6},{105.2,105.4,101.6,102},{102.1,103.8,101.2,101.5}});
    CHECK(kind(ufd,1,105.6,3,103.8,FPK_UFVG,2));
    auto spb=bars({{100,100.7,99.3,100.5},{100.5,100.9,99.9,100.1},{100.1,101.5,99.8,101.2},{101.6,105,101.3,104.6},{105.1,106.3,103,105.9}});
    CHECK(kind(spb,2,101.2,4,105.1,FPK_SPB,1));                            // outer edge to outer edge of the two imbalances
    CHECK(kind(spb,2,101.5,4,103,FPK_FVG,1));
    auto spb2=bars({{100,100.6,99.4,100.3},{100.3,101.9,100.1,101.2},{101.5,103.4,101.3,103},{103.3,104.2,101.7,103.9}});
    CHECK(kind(spb2,1,101.2,3,103.3,FPK_SPB,1));                           // no FVG needed: candles 1 and 3 overlap
    auto ob=bars({{103,103.4,101.9,102.2},{102.2,102.6,100.8,101.1},{101.1,101.5,99.6,100.4}});
    CHECK(kind(ob,2,99.6,2,101.1,FPK_OB,1));                               // down-close candle, low to open
    CHECK(kind(ob,2,99.6,2,101.5,FPK_OB,1));                               // high to low
    CHECK(kind(ob,2,100.4,2,101.1,FPK_OB,1));                              // body only
    CHECK(kind(ob,2,101.5,2,100.4,FPK_OB,1));                              // high to close: body and upper wick
    auto obu=bars({{99,100.2,98.7,99.9},{99.9,101.1,99.6,100.8},{100.8,102.5,100.5,101.9}});
    CHECK(kind(obu,2,102.5,2,100.8,FPK_OB,2));                             // up-close candle, high to open
    auto pw=bars({{101.7,102.6,101.4,102.4},{102.4,105.2,101.6,101.9}});
    CHECK(kind(pw,1,105.2,1,102.4,FPK_PW,0));
    auto dw=bars({{102.7,103,102,102.3},{102.2,103.2,99,102.9}});
    CHECK(kind(dw,1,99,1,102.2,FPK_DW,0));
    auto kr=bars({{101,101.4,99.6,99.9},{99.9,100.3,98.8,100.1},{100.1,101.9,99.8,101.6},{101.6,103,101.2,102.7},{102.7,104.4,102.3,104}});
    CHECK(kind(kr,1,98.8,4,104.4,FPK_KR,0) && kind(kr,4,104.4,1,98.8,FPK_KR,0));
    CHECK(kind(kr,1,100.3,4,102.3,FPK_NONE,0));                            // a high below a low across 4 candles
    CHECK(kind(kr,4,104.4,-1,0,FPK_KH,0) && kind(kr,1,98.8,-1,0,FPK_KL,0) && kind(kr,1,99.9,-1,0,FPK_NONE,0));
   }
   // ---- factory styles, colours by timeframe, names
   {
    FPSetup f;FPFactoryStyle(FPK_FVG,f);
    bool ok=f.count==12 && !f.fill && f.ray_right && f.label_h==1 && f.label_float && f.base_color==clrNONE && !f.diagonal;
    double want[]={0,.125,.25,.375,.5,.62,.625,.705,.75,.79,.875,1};
    int style[]={STYLE_DASH,STYLE_DASHDOTDOT,STYLE_DASHDOT,STYLE_DASHDOTDOT,STYLE_DOT,STYLE_SOLID,STYLE_DASHDOTDOT,STYLE_SOLID,STYLE_DASHDOT,STYLE_SOLID,STYLE_DASHDOTDOT,STYLE_DASH};
    bool on[]={true,false,true,false,true,false,false,false,true,false,false,true};
    for(int i=0;i<12 && ok;i++)ok=f.levels[i].value==want[i] && f.levels[i].style==style[i] && f.levels[i].enabled==on[i];
    CHECK(ok);
    CHECK(f.levels[0].description=="%n" && f.levels[5].description=="62" && f.levels[7].description=="70.5" && f.levels[9].description=="79" && f.levels[4].description=="");
    CHECK(f.levels[5].ink==clrWhite && f.levels[7].ink==clrWhite && f.levels[9].width==1);
    FPSetup o;FPFactoryStyle(FPK_OB,o);CHECK(o.levels[0].style==STYLE_SOLID && o.levels[11].style==STYLE_SOLID && o.levels[2].style==STYLE_DASHDOT && o.levels[4].style==STYLE_DOT);
    FPSetup k;FPFactoryStyle(FPK_KH,k);CHECK(k.hline && k.count==1 && k.levels[0].style==STYLE_SOLID && k.levels[0].description=="%n");
    CHECK(FPTierColor(PERIOD_MN1)==InpColorMN && FPTierColor(PERIOD_W1)==InpColorW1 && FPTierColor(PERIOD_D1)==InpColorD1);
    CHECK(FPTierColor(PERIOD_H12)==InpColorH4 && FPTierColor(PERIOD_H4)==InpColorH4 && FPTierColor(PERIOD_H3)==InpColorH1 && FPTierColor(PERIOD_H1)==InpColorH1);
    CHECK(FPTierColor(PERIOD_M30)==InpColorM15 && FPTierColor(PERIOD_M15)==InpColorM15 && FPTierColor(PERIOD_M12)==InpColorM5 && FPTierColor(PERIOD_M5)==InpColorM5);
    CHECK(FPTierColor(PERIOD_M4)==InpColorM1 && FPTierColor(PERIOD_M1)==InpColorM1);
    CHECK(FPTierWidth(PERIOD_MN1)==2 && FPTierWidth(PERIOD_D1)==2 && FPTierWidth(PERIOD_H12)==1 && FPTierWidth(PERIOD_M1)==1);
    CHECK(InpColorMN==(color)(255|102<<8|184<<16) && InpColorM1==(color)(140|140<<8|140<<16));   // the measured palette
    CHECK(FPLevelNumber(.705)=="70.5" && FPLevelNumber(.62)=="62");
   }
   // ---- created drawings: type, direction, name, colours, widths, the tag on top
   g_bars.clear();
   {
    double v[][4]={{106,106.8,105.6,106.4},{106.4,106.9,105.9,106.1},{106.1,106.4,105,105.3},{105.5,105.7,101.4,101.8},{101.9,103.6,101,101.4},{101.4,103,101.1,102.8},{102.8,104,102.6,103.9}};
    for(int i=0;i<7;i++){MqlRates m{};m.time=(datetime)(7200000+i*14400);m.open=v[i][0];m.high=v[i][1];m.low=v[i][2];m.close=v[i][3];g_bars.push_back(m);}
   }
   FPSetup fv;NewSetup(fv);fv.source_tf=PERIOD_H4;fv.ta=g_bars[2].time;fv.pa=105;fv.tb=g_bars[4].time;fv.pb=103.6;fv.left=fv.ta;fv.right=fv.tb;
   AutoType(fv);
   CHECK(fv.kind==FPK_FVG && fv.dir==2 && fv.name.rfind("H4 FVG ",0)==0 && !fv.fill && fv.ray_right && fv.count==12);
   CHECK(fv.levels[0].ink==InpColorH4 && fv.levels[0].width==1 && fv.levels[5].ink==clrWhite && fv.base_color==InpColorH4);
   CHECK(fv.levels[11].description=="%n" && fv.levels[0].description=="");    // 100% (candle 1's low) is the upper edge here
   CHECK(LevelText(fv.levels[11],105,fv.name)==fv.name);
   {
    FPSetup d;NewSetup(d);d.source_tf=PERIOD_D1;d.ta=g_bars[2].time;d.pa=105;d.tb=g_bars[4].time;d.pb=103.6;d.left=d.ta;d.right=d.tb;AutoType(d);
    CHECK(d.levels[0].width==2 && d.levels[0].ink==InpColorD1 && d.levels[5].width==1 && d.name.rfind("D1 FVG",0)==0);
    FPSetup u;NewSetup(u);u.source_tf=PERIOD_H4;u.ta=g_bars[1].time;u.pa=106.5;u.tb=g_bars[3].time;u.pb=102;u.left=u.ta;u.right=u.tb;AutoType(u);
    CHECK(u.kind==FPK_NONE && u.levels[0].style==STYLE_SOLID && u.name=="H4 Fib 1");                 // unmatched: KR style
    // A line drawn on a template's 50% level keeps its price once it becomes a one-level KH.
    FPSetup l;NewSetup(l);l.source_tf=PERIOD_H1;l.hline=true;l.count=1;DefaultLevel(l.levels[0],.5);
    l.pb=106.4;l.pa=107.4;l.left=g_bars[1].time;l.right=l.left+36000;l.ta=l.left;l.tb=l.right;l.ray_right=true;
    AutoType(l);
    CHECK(l.kind==FPK_KH && l.count==1 && LineLevel(l)==0 && std::fabs(FPLevelPrice(l.pa,l.pb,l.levels[0].value)-106.9)<1e-9 && l.name=="H1 KH 1" && l.ray_right);
    FPSetup ld;NewSetup(ld);ld.source_tf=PERIOD_H1;ld.hline=true;ld.count=1;DefaultLevel(ld.levels[0],0);
    ld.pb=106.9;ld.pa=107.9;ld.left=g_bars[1].time;ld.right=ld.left+36000;ld.ta=ld.left;ld.tb=ld.right;ld.ray_right=false;
    AutoType(ld);CHECK(ld.kind==FPK_KH && !ld.ray_right);                     // a line dragged to length stays that length
    FPSetup mn;NewSetup(mn);mn.source_tf=PERIOD_MN1;mn.kind=FPK_KR;CHECK(FPDefaultName(mn)=="MN KR 1");
    mn.source_tf=PERIOD_H4;mn.kind=FPK_FVG;mn.dir=1;CHECK(FPDefaultName(mn)=="H4 FVG 1 "+Glyph(0x25B2));
    mn.dir=2;CHECK(FPDefaultName(mn)=="H4 FVG 1 "+Glyph(0x25BC));mn.dir=0;CHECK(FPDefaultName(mn)=="H4 FVG 1");
   }
   // ---- saved with the drawing; files from earlier versions read as untyped and unused
   {
    FPSetup a=fv;a.kind=FPK_KR;a.dir=1;a.used=true;a.used_ray=true;
    int f=FileOpen("rt.bin",FILE_WRITE|FILE_BIN,'\t',0);WriteSetup(f,a);FileWriteInteger(f,0,4);FileClose(f);
    FPSetup b;f=FileOpen("rt.bin",FILE_READ|FILE_BIN,'\t',0);bool ok=ReadSetup(f,b);FileClose(f);
    CHECK(ok && b.kind==FPK_KR && b.dir==1 && b.used && b.used_ray && b.name==a.name);
    a.kind=FPK_NONE;a.dir=0;a.used=false;a.used_ray=false;
    f=FileOpen("rt.bin",FILE_WRITE|FILE_BIN,'\t',0);WriteSetup(f,a);FileWriteInteger(f,0,4);FileClose(f);
    f=FileOpen("rt.bin",FILE_READ|FILE_BIN,'\t',0);ok=ReadSetup(f,b);FileClose(f);
    CHECK(ok && b.kind==FPK_NONE && !b.used);
   }
   // ---- used: stops at the first candle that traded into it, fades, and extends again
   {
    datetime keep_now=g_test_now;g_test_now=g_bars[6].time+60;
    FPSetup s=fv;MarkUsed(s,true);
    CHECK(s.used && s.used_ray && !s.ray_right && s.right==g_bars[6].time);   // bar 6 is the first back into the gap
    MarkUsed(s,false);CHECK(!s.used && s.ray_right);
    FPSetup r=fv;r.kind=FPK_KR;MarkUsed(r,true);CHECK(r.used && r.right>r.left);   // a range stops at the latest bar
    MQLArr<string> lines;color accent=clrNONE;FibTip(s,0,lines,accent);
    bool status=false;for(int q=0;q<ArraySize(lines);q++)if(lines[q]=="Status\tUsed")status=true;CHECK(!status);
    MarkUsed(s,true);FibTip(s,0,lines,accent);status=false;for(int q=0;q<ArraySize(lines);q++)if(lines[q]=="Status\tUsed")status=true;CHECK(status);
    g_test_now=keep_now;
    // A used drawing is drawn faded.
    g_count=1;FPSetup &z=g_sets[0];MakeFib(z,77,"Faded",false,PERIOD_H1);
    z.ta=(datetime)(g_xy_t0+60*100);z.tb=(datetime)(g_xy_t0+60*300);z.left=z.ta;z.right=z.tb;z.pa=1.14;z.pb=1.13;
    auto alpha_at=[&](int y){int faded=0,full=0;for(auto& q:g_rects)if(!q.fill && q.y0<=y && y<=q.y1 && q.x0>=100 && q.x1<=300){if((q.c>>24)==FP_USED_ALPHA)faded++;else if((q.c>>24)==255)full++;}return std::make_pair(faded,full);};
    z.used=true;g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
    auto u1=alpha_at(180);CHECK(u1.first>0 && u1.second==0);
    z.used=false;g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
    auto u2=alpha_at(180);CHECK(u2.first==0 && u2.second>0);
   }
   // ---- Fibo levels tab: sort, all widths, level groups, drag a row, defaults, used
   {
    g_count=1;g_sets[0]=fv;g_selected=0;g_store="mem.bin";OpenEditor();CHECK(g_editor);
    g_tab=2;g_page=0;g_ui_dirty=true;BuildUI();
    CHECK(RegFind(UIS("E.Drag1"))>=0 && RegFind(UIS("E.Sort"))>=0 && RegFind(UIS("E.AllWidth"))>=0 && RegFind(UIS("E.Group2"))>=0);
    Click(UIS("E.Sort"));Click(UIS("E.Sort"));
    CHECK(g_edit.levels[0].value==1 && g_edit.levels[11].value==0);           // high to low
    Click(UIS("E.Sort"));CHECK(g_edit.levels[0].value==0);
    Click(UIS("E.AllWidth"));CHECK(g_popup==2 && g_popup_row==-1);DropdownChoice(2);ClosePopup();
    {bool w3=true;for(int i=0;i<g_edit.count;i++)w3=w3 && g_edit.levels[i].width==3;CHECK(w3);}
    CHECK(FPGroupState(g_edit,2)==2);Click(UIS("E.Group2"));CHECK(FPGroupState(g_edit,2)==1);
    Click(UIS("E.Group2"));CHECK(FPGroupState(g_edit,2)==2);Click(UIS("E.Group3"));CHECK(FPGroupState(g_edit,3)==1);
    g_ui_dirty=true;BuildUI();
    double moved=g_edit.levels[1].value;
    int ri=RegFind(UIS("E.Drag1"));CHECK(ri>=0);
    if(ri>=0)
      {
       int hx=g_reg[ri].x+2,hy=g_reg[ri].y+2;
       LevelDragMouse(hx,hy,true,false);CHECK(g_lvdrag && g_lvdrag_from==1);
       LevelDragMouse(hx,LevelRowY(3)+5,true,true);CHECK(g_lvdrag_to==3 && RegFind(UIS("E.Drop"))>=0);
       LevelDragMouse(hx,LevelRowY(3)+5,false,true);CHECK(!g_lvdrag && g_edit.levels[3].value==moved && RegFind(UIS("E.Drop"))<0);
       Click(UIS("E.Sort"));CHECK(g_edit.levels[3].value==moved);              // the release does not click the button under it
      }
    g_ignore_editor_click_until=0;
    Click(UIS("E.Defaults"));CHECK(g_edit.count==12 && g_edit.levels[1].value==.125 && g_edit.levels[1].width==1 && !g_edit.levels[1].enabled);
    g_tab=0;g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("E.Used"))>=0);                 // the Common tab
    Click(UIS("E.Used"));CHECK(g_edit.used && !g_edit.ray_right);g_ui_dirty=true;BuildUI();
    Click(UIS("E.Used"));CHECK(!g_edit.used && g_edit.ray_right);
    CloseEditor();
   }
   // ---- built-in presets: installed once, deletable, restorable; they colour by timeframe
   {
    string folder="FibonacciPro\\Presets\\";
    for(int i=0;i<FP_BUILTIN_COUNT;i++)g_disk.erase(folder+FPBuiltinName(i)+".fpp");
    g_disk.erase(FP_BUILTIN_MARKER);
    FPInstallBuiltinsOnce();
    bool all=FileIsExist(FP_BUILTIN_MARKER,0);for(int i=0;i<FP_BUILTIN_COUNT;i++)all=all && FileIsExist(folder+FPBuiltinName(i)+".fpp",0);CHECK(all);
    g_disk.erase(folder+"VI.fpp");FPInstallBuiltinsOnce();CHECK(!FileIsExist(folder+"VI.fpp",0));   // a deleted built-in stays deleted
    FPSetup ote;CHECK(ReadPreset(folder+"KR + OTE.fpp",ote) && FPGroupState(ote,3)==1 && ote.base_color==clrNONE);
    g_count=1;g_sets[0]=fv;g_selected=0;OpenEditor();PresetBrowser(false);CHECK(RegFind(Obj("R.Restore"))>=0);
    Click(Obj("R.Restore"));CHECK(!FileIsExist(folder+"VI.fpp",0));                // first click only asks
    Click(Obj("R.Restore"));CHECK(FileIsExist(folder+"VI.fpp",0));
    // Your own FVG preset is the style of new FVGs (here with the octants on).
    FPSetup mine;FPFactoryStyle(FPK_FVG,mine);for(int i=0;i<mine.count;i++)if(FPInGroup(mine.levels[i].value,2))mine.levels[i].enabled=true;
    CHECK(WritePreset(folder+"FVG.fpp",mine));
    FPSetup s2;NewSetup(s2);s2.source_tf=PERIOD_H4;s2.ta=g_bars[2].time;s2.pa=105;s2.tb=g_bars[4].time;s2.pb=103.6;s2.left=s2.ta;s2.right=s2.tb;
    AutoType(s2);CHECK(s2.kind==FPK_FVG && FPGroupState(s2,2)==1 && s2.levels[1].ink==InpColorH4);
    // Loading a built-in colours by timeframe; a preset with its own colours keeps them.
    ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,"OB");PresetAction();
    CHECK(g_edit.levels[0].style==STYLE_SOLID && g_edit.levels[0].ink==InpColorH4 && g_edit.base_color==InpColorH4);
    FPSetup red;FPFactoryStyle(FPK_KR,red);red.base_color=clrRed;for(int i=0;i<red.count;i++)red.levels[i].ink=clrRed;
    CHECK(WritePreset(folder+"Red.fpp",red));
    PresetBrowser(false);ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,"Red");PresetAction();CHECK(g_edit.levels[0].ink==clrRed);
    // Saving from a drawing in its timeframe colour keeps the preset coloured by timeframe.
    FPResetLevels(g_edit);CHECK(FPUsesTierInk(g_edit));
    PresetBrowser(true);ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,"Mine");PresetAction();
    FPSetup back;CHECK(ReadPreset(folder+"Mine.fpp",back) && back.base_color==clrNONE);
    ClosePopup();CloseEditor();
   }
   // ---- drawing with the mouse: the type, style and name arrive on release
   {
    g_count=0;g_selected=-1;g_editor=false;g_list=false;g_popup=0;g_store="mem.bin";g_owner=true;
    Arm();CHECK(g_armed);
    BeginMouse(200,180);MoveMouse(400,240);EndMouse(400,240);
    CHECK(g_count==1 && g_sets[0].name=="H1 Fib 1" && g_sets[0].count==12 && !g_sets[0].fill && g_sets[0].levels[0].style==STYLE_SOLID);
    Arm();BeginMouse(300,200);EndMouse(300,200);                              // a single click: a line
    CHECK(g_count==2 && g_sets[1].hline && g_sets[1].name=="H1 Line 1" && g_sets[1].count==1 && g_sets[1].levels[0].ink==InpColorH1);
    g_count=0;g_selected=-1;
   }
   // ---- drawings list: the type column and the Used switch
   {
    g_count=1;g_sets[0]=fv;g_sets[0].used=false;g_selected=-1;g_list=true;g_editor=false;g_ui_dirty=true;BuildUI();
    CHECK(RegFind(UIS("L.Used0"))>=0 && g_texts[UIS("L.Type0")]=="FVG");
    ListClick("L.Used0");CHECK(g_sets[0].used && !g_sets[0].ray_right);
    ListClick("L.Used0");CHECK(!g_sets[0].used && g_sets[0].ray_right);
    g_list=false;g_count=0;g_ui_dirty=true;
   }

   // ======================================================== 1.66: lot size & risk
   // ---- the calculation
   {
    CHECK(FPLotDigits(0.01)==2 && FPLotDigits(0.1)==1 && FPLotDigits(1)==0 && FPLotDigits(0.05)==2 && FPLotDigits(0.001)==3);
    int f=9;
    CHECK(std::fabs(FPRiskLots(100,20,1,0,0.01,100,0.01,f)-5.0)<1e-12 && f==0);        // US100: 20 points at 1 USD per point
    CHECK(std::fabs(FPRiskLots(100,30,1,0,0.01,100,0.01,f)-3.33)<1e-12 && f==0);       // rounded down, never up
    CHECK(std::fabs(FPRiskLots(100,20,1,5,0.01,100,0.01,f)-4.0)<1e-12 && f==0);        // commission adds to the loss
    CHECK(FPRiskLots(0.1,20,1,0,0.01,100,0.01,f)==0 && f==1);                          // below the minimum volume
    CHECK(FPRiskLots(1,20,1,0,0.1,100,0.01,f)==0 && f==1);                             // 0.05 lots with a 0.1 minimum
    CHECK(std::fabs(FPRiskLots(3,20,1,0,0.1,100,0.01,f)-0.15)<1e-12 && f==0);          // above it, the 0.01 step applies
    CHECK(std::fabs(FPRiskLots(1e6,1,1,0,0.01,100,0.01,f)-100)<1e-12 && f==2);         // capped at the maximum
    CHECK(std::fabs(FPRiskLots(100,30,1,0,0.1,100,0.1,f)-3.3)<1e-12 && f==0);          // a 0.1 step
    CHECK(std::fabs(FPRiskLots(70,7,1,0,0.01,100,0.01,f)-10.0)<1e-12);                 // an exact quotient is not a step short
    CHECK(std::fabs(FPRiskLots(100,0.0020,100000,0,0.01,100,0.01,f)-0.5)<1e-12);       // EURUSD: 20 pips at 10 USD per pip
    CHECK(FPRiskLots(100,0,1,0,0.01,100,0.01,f)==0 && f==-1);
    CHECK(FPRiskLots(0,10,1,0,0.01,100,0.01,f)==0 && f==-1 && FPRiskLots(100,10,0,0,0.01,100,0.01,f)==0 && f==-1);
    // Over random cases: the loss never exceeds the risk, and one more step would.
    bool safe=true;unsigned seed=7;
    for(int i=0;i<20000;i++)
      {
       seed=seed*1103515245+12345;double risk=1+(seed%100000)/10.0;
       seed=seed*1103515245+12345;double dist=0.0001+(seed%50000)/1000.0;
       seed=seed*1103515245+12345;double value=0.01+(seed%100000)/10.0;
       seed=seed*1103515245+12345;double comm=(seed%20)/2.0;
       double steps[]={0.01,0.1,1,0.05};double step=steps[(seed>>8)%4];
       double lots=FPRiskLots(risk,dist,value,comm,0,0,step,f),per=dist*value+comm;
       if(f==0 && lots*per>risk*(1+1e-6))safe=false;
       if(f==0 && (lots+step)*per<=risk*(1-1e-6))safe=false;
       if(f==1 && step*per<=risk*(1-1e-6))safe=false;
      }
    CHECK(safe);
    CHECK(FPRiskAmount(0,150,1,0,10000,9000)==150 && FPRiskAmount(1,0,1.5,0,10000,9000)==150 && FPRiskAmount(2,0,1,0,10000,9000)==90 && FPRiskAmount(3,0,0.5,50000,10000,9000)==250);
    CHECK(FPRiskSide(true,0,1.0990,1.1000,1.1001)==1 && FPRiskSide(true,0,1.1010,1.1000,1.1001)==-1 && FPRiskSide(true,0,1.10005,1.1000,1.1001)==0 && FPRiskSide(true,0,1.0,0,0)==0);
    CHECK(FPRiskSide(false,1.1,1.09,0,0)==1 && FPRiskSide(false,1.1,1.11,0,0)==-1 && FPRiskSide(false,1.1,1.1,0,0)==0);
    CHECK(FPRiskEntry(true,1,0,1.1000,1.1001)==1.1001 && FPRiskEntry(true,-1,0,1.1000,1.1001)==1.1000 && FPRiskEntry(false,1,1.05,1.1,1.1001)==1.05);
    CHECK(std::fabs(FPTargetPrice(100,90,2)-120)<1e-12 && std::fabs(FPTargetPrice(100,110,2)-80)<1e-12);
    CHECK(std::fabs(FPTargetR(100,90,125)-2.5)<1e-12 && std::fabs(FPTargetR(100,110,85)-1.5)<1e-12 && FPTargetR(100,100,120)==0);
    CHECK(FPNormTick(18000.13,0.25,2)==18000.25 && FPNormTick(18000.12,0.25,2)==18000.0 && FPNormTick(1.234567,0.00001,5)==1.23457);
    MQLArr<double> r;
    CHECK(FPParseRList("2",r,8)==1 && r[0]==2);
    CHECK(FPParseRList("3 1 2",r,8)==3 && r[0]==1 && r[1]==2 && r[2]==3);
    CHECK(FPParseRList(" 1.5, 3;5 ",r,8)==3 && r[0]==1.5 && r[2]==5 && FPRListText(r,3)=="1.5 3 5");
    CHECK(FPParseRList("2 2",r,8)==1 && FPParseRList("",r,8)==0 && FPParseRList("abc",r,8)==-1 && FPParseRList("-1",r,8)==-1);
    CHECK(FPParseRList("0",r,8)==-1 && FPParseRList("101",r,8)==-1 && FPParseRList("1 2 3 4 5 6 7 8 9 10",r,8)==8 && r[7]==8);
    CHECK(FPMoney(12345.678)=="12,345.68" && FPMoney(-1234.5)=="-1,234.50" && FPMoney(999)=="999.00" && FPMoney(1000)=="1,000.00");
    CHECK(FPMoney(0)=="0.00" && FPMoney(1234567)=="1,234,567.00" && FPMoney(-0.001)=="0.00");
    CHECK(FPRNum(2)=="2" && FPRNum(1.5)=="1.5" && FPRNum(10)=="10" && RiskNumText(0.0125)=="0.0125" && RiskNumText(100)=="100");
    double v=0;bool dis=false;
    CHECK(FPValueDecide(5,2,1,10,v,dis)==1 && v==5 && dis);               // your own value first
    CHECK(FPValueDecide(0,2,1,10,v,dis)==2 && v==2 && dis);               // then the calibration
    CHECK(FPValueDecide(0,0,1,10,v,dis)==0 && v==0 && dis);               // methods that disagree: no size
    CHECK(FPValueDecide(0,0,1,1.01,v,dis)==3 && v==1.01 && !dis);         // agreeing methods: the larger
    CHECK(FPValueDecide(0,0,1,1.03,v,dis)==0 && dis);                     // 3% apart is a disagreement
    CHECK(FPValueDecide(0,0,1,0,v,dis)==4 && v==1 && FPValueDecide(0,0,0,3,v,dis)==5 && v==3 && FPValueDecide(0,0,0,0,v,dis)==0);
    CHECK(FPPendingName(1,1.09,1.1,1.1001)=="BUY LIMIT" && FPPendingName(1,1.11,1.1,1.1001)=="BUY STOP");
    CHECK(FPPendingName(-1,1.11,1.1,1.1001)=="SELL LIMIT" && FPPendingName(-1,1.09,1.1,1.1001)=="SELL STOP");
    CHECK(FPIsFiat("USD") && FPIsFiat("JPY") && !FPIsFiat("XAU") && !FPIsFiat("US"));
    // a fourth shortcut
    int key=0;bool c=false,s2=false,a=false;
    CHECK(ParseHotkey(InpRiskHotkey,key,c,s2,a) && key=='R' && c && s2 && !a);
    g_risk_key='R';g_risk_ctrl=true;g_risk_shift=true;g_risk_alt=false;CHECK(!ShortcutsClash());
    g_risk_key='K';CHECK(ShortcutsClash());g_risk_key='R';
   }
   // ---- risk settings: one file per account, verified on save, damaged files refused
   {
    FPRiskConfig c;FPRDefaults(c);
    CHECK(c.mode==1 && c.percent==1 && c.entry==0 && c.targets=="2" && c.add_r=="3" && c.count==0);
    c.mode=3;c.percent=0.5;c.base=50000;c.entry=1;c.targets="1 2 3";
    CHECK(FPRSymSet(c,"US100",0,1.0) && FPRSymSet(c,"EURUSD",7,0) && c.count==2);
    CHECK(FPRCommission(c,"EURUSD")==7 && FPRManual(c,"US100")==1.0 && FPRManual(c,"XAU")==0 && FPRCommission(c,"XAU")==0);
    CHECK(FPRWriteFile("rt.risk",c));
    FPRiskConfig d;FPRDefaults(d);
    CHECK(FPRReadFile("rt.risk",d) && d.mode==3 && d.base==50000 && d.entry==1 && d.targets=="1 2 3" && d.count==2 && d.syms[1].symbol=="EURUSD" && d.syms[1].commission==7);
    CHECK(FPRSymSet(c,"US100",0,0) && c.count==1 && c.syms[0].symbol=="EURUSD");      // nothing of its own left: removed
    string keep=g_disk["rt.risk"];g_disk["rt.risk"]=keep.substr(0,keep.size()-3);
    FPRiskConfig e;FPRDefaults(e);CHECK(!FPRReadFile("rt.risk",e) && e.mode==1);
    g_disk["rt.risk"]=keep;
    FPRiskConfig full;FPRDefaults(full);bool ok=true;
    for(int i=0;i<FPR_MAX_SYMS;i++)ok=ok && FPRSymSet(full,"S"+std::to_string(i),1,0);
    CHECK(ok && !FPRSymSet(full,"NEW",1,0) && FPRSymSet(full,"S5",2,0) && FPRCommission(full,"S5")==2);
   }
   // ---- calibration file (same code as the script): verified, damaged files refused
   {
    MQLArr<FPCalib> list;ArrayResize(list,2);
    list[0].symbol="US100";list[0].profit_ccy="USD";list[0].account_ccy="USD";list[0].value_profit=1;list[0].value_account=1;
    list[0].contract=1;list[0].tick_size=0.01;list[0].tick_value=0.1;list[0].time=1000;
    list[1]=list[0];list[1].symbol="DE40";list[1].profit_ccy="EUR";list[1].value_account=1.08;
    CHECK(FPCSave("c.calib",list,2));
    MQLArr<FPCalib> back;CHECK(FPCLoad("c.calib",back)==2 && back[1].symbol=="DE40" && back[1].value_account==1.08 && back[0].time==1000);
    CHECK(FPCFind(back,2,"DE40")==1 && FPCFind(back,2,"XX")==-1);
    string keep=g_disk["c.calib"];g_disk["c.calib"]=keep+"x";CHECK(FPCLoad("c.calib",back)==-1 && ArraySize(back)==0);
    g_disk["c.calib"]=keep;CHECK(FPCLoad("missing.calib",back)==-1);
   }
   // ---- the value of a lot: contract size checked against the tick value; calibration; your own value
   {
    ClearMarket();g_acc_ccy="USD";g_server="Test-Server";g_login=1234;
    AddSym("EURUSD","EUR","USD",SYMBOL_CALC_MODE_FOREX,1.1,1.1001,5,0.00001,1.0,100000,true);
    AddSym("US100","USD","USD",SYMBOL_CALC_MODE_CFDINDEX,18000,18001,2,0.01,0.1,1,true);       // the broker's tick value is 10x too high
    AddSym("DE40","EUR","EUR",SYMBOL_CALC_MODE_CFDINDEX,19000,19002,1,0.1,0.11,1,true);          // 0.1 x 1 x 1.10 = 0.11 USD
    AddSym("USDJPY","USD","JPY",SYMBOL_CALC_MODE_FOREX,150,150.01,3,0.001,0.6666,100000,true);
    AddSym("GBPUSD","GBP","USD",SYMBOL_CALC_MODE_FOREX,1.25,1.2501,5,0.00001,1.0,100000,false); // not in Market Watch
    string sym0=_Symbol;int dig0=_Digits;double pt0=_Point;
    FPRDefaults(g_rcfg);g_reditor=false;g_disk.erase(FPCFile());
    _Symbol="EURUSD";g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
    CHECK(std::fabs(g_rval.contract-100000)<1e-6 && std::fabs(g_rval.tick-100000)<1e-6 && !g_rcal_found);
    double v=0;bool dis=false;
    CHECK(FPValueDecide(0,g_rval.calib,g_rval.contract,g_rval.tick,v,dis)==3 && !dis);
    CHECK(g_rsym.fx && std::fabs(RiskPip()-0.0001)<1e-15 && RiskUnitText()=="per pip (0.00010)" && RiskMoveText(-0.0021)=="-21.0 pips");
    _Symbol="US100";_Digits=2;_Point=0.01;g_rconv_key="";RiskRefreshValue();
    CHECK(std::fabs(g_rval.contract-1)<1e-9 && std::fabs(g_rval.tick-10)<1e-9);
    CHECK(FPValueDecide(0,g_rval.calib,g_rval.contract,g_rval.tick,v,dis)==0 && dis);                  // blocked
    CHECK(!g_rsym.fx && RiskUnitText()=="per 1.0 move" && RiskMoveText(25.5)=="+25.50");
    // On the chart: no size, and the reason.
    RiskReset();g_risk.active=true;g_risk.market=true;g_risk.stop=17980;g_risk.ntp=1;g_risk.tp_r[0]=2;g_risk.tp_fixed[0]=true;
    RiskComputeWith(g_rcfg);
    CHECK(g_rview.side==1 && g_rview.lots==0 && g_rview.flag==-1 && g_rview.why.find("disagree")!=string::npos && RiskEntryText().find("no size")!=string::npos);
    // Your own value sizes it: 21 points at 1 USD, 1% of 10,000 -> 4.76 lots.
    FPRSymSet(g_rcfg,"US100",0,1.0);RiskComputeWith(g_rcfg);
    CHECK(g_rval.source==1 && std::fabs(g_rview.lots-4.76)<1e-12 && std::fabs(g_rview.tp[0]-18043)<1e-9);
    FPRSymSet(g_rcfg,"US100",0,0);
    _Symbol="DE40";_Digits=1;_Point=0.1;g_rconv_key="";RiskRefreshValue();
    CHECK(std::fabs(g_rval.contract-1.1)<1e-9 && std::fabs(g_rval.tick-1.1)<1e-9 && !g_rsym.fx);      // EUR profit at the EURUSD bid
    AddSym("EURUSD.c","EUR","USD",SYMBOL_CALC_MODE_CFD,1.1,1.1001,5,0.00001,1.0,100000,true);   // forex set up as a CFD
    _Symbol="EURUSD.c";_Digits=5;_Point=0.00001;RiskRefreshValue();CHECK(g_rsym.fx && std::fabs(g_rval.contract-100000)<1e-6);
    _Symbol="USDJPY";_Digits=3;_Point=0.001;g_rconv_key="";RiskRefreshValue();
    CHECK(std::fabs(g_rval.contract-100000/150.01)<1e-6 && RiskUnitText()=="per pip (0.010)");         // JPY to USD: 1 / the USDJPY ask
    // A GBP account: USD profit converted with GBPUSD, found outside Market Watch and added to it.
    g_acc_ccy="GBP";_Symbol="US100";_Digits=2;_Point=0.01;g_rconv_key="";g_selects=0;RiskRefreshValue();
    CHECK(std::fabs(g_rval.contract-1/1.2501)<1e-9 && g_selects==1 && g_syms["GBPUSD"].watch);
    g_acc_ccy="USD";
    // The calibration: per server, kept in the profit currency, converted at today's rate.
    MQLArr<FPCalib> list;ArrayResize(list,2);
    list[0].symbol="US100";list[0].profit_ccy="USD";list[0].account_ccy="USD";list[0].value_profit=1;list[0].value_account=1;
    list[0].contract=1;list[0].tick_size=0.01;list[0].tick_value=0.1;list[0].time=1000;
    list[1]=list[0];list[1].symbol="DE40";list[1].profit_ccy="EUR";list[1].value_profit=1;list[1].value_account=1.05;
    CHECK(FPCFile()=="FibonacciPro\\Test-Server.calib" && FPCSave(FPCFile(),list,2));
    g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
    CHECK(g_rcal_found && std::fabs(g_rval.calib-1)<1e-12);
    CHECK(FPValueDecide(0,g_rval.calib,g_rval.contract,g_rval.tick,v,dis)==2 && v==1);                 // sizes despite the bad tick value
    RiskComputeWith(g_rcfg);CHECK(g_rval.source==2 && std::fabs(g_rview.lots-4.76)<1e-12);
    _Symbol="DE40";_Digits=1;_Point=0.1;g_rconv_key="";RiskLoadCalibration(true);RiskRefreshValue();
    CHECK(std::fabs(g_rval.calib-1.1)<1e-9);                                                           // 1 EUR at today's 1.10, not 1.05 then
    g_syms["DE40"].contract=10;RiskRefreshValue();
    CHECK(g_rval.calib==0 && g_rval.calib_stale);                                                      // contract changed: run the script again
    g_syms["DE40"].contract=1;
    // Without a rate to convert, the account-currency value of the calibration is used.
    for(string gone:{"EURUSD","EURUSD.c"}){g_syms.erase(gone);g_watch.erase(std::find(g_watch.begin(),g_watch.end(),gone));g_all.erase(std::find(g_all.begin(),g_all.end(),gone));}
    g_rconv_key="";
    RiskRefreshValue();CHECK(std::fabs(g_rval.calib-1.05)<1e-9 && g_rval.contract==0);
    g_disk.erase(FPCFile());RiskReset();
    _Symbol=sym0;_Digits=dig0;_Point=pt0;
   }
   // ---- the measurement: press at the market, drag to the stop, release
   {
    ClearMarket();g_acc_ccy="USD";g_server="Test-Server";g_login=1234;g_balance=10000;g_equity=10000;
    AddSym("EURUSD","EUR","USD",SYMBOL_CALC_MODE_FOREX,1.10000,1.10010,5,0.00001,1.0,100000,true);
    g_disk.erase(FPCFile());
    g_zact.enabled=false;g_zcfg.enabled=false;
    g_count=0;g_selected=-1;g_editor=false;g_list=false;g_zeditor=false;g_reditor=false;g_popup=0;g_owner=true;g_hidden=false;g_armed=false;g_drag=0;
    g_rstore="mem.risk";g_disk.erase("mem.risk");LoadRisk();CHECK(!g_rstore_found && g_rcfg.mode==1 && !g_risk.armed);
    // The first use opens the Risk window, so the risk per trade is checked first.
    RiskArm();CHECK(g_risk.armed && g_reditor);
    RiskPanelClick("Cancel");RiskClear();RiskArm();CHECK(g_risk.armed && !g_reditor);       // only once per session
    OpenRisk();g_redit.mode=0;g_redit.amount=100;CHECK(ApplyRisk(true) && !g_reditor && g_rstore_found && g_rcfg.mode==0 && FileIsExist("mem.risk",0));
    g_ui_dirty=true;BuildUI();
    CHECK(RegFind(UIS("K.Market"))>=0 && RegFind(UIS("K.Add"))>=0 && RegFind(UIS("K.R"))>=0 && RegFind(UIS("T.Risk"))>=0);
    CHECK(g_texts[UIS("K.Risk")]=="Risk 100.00 USD" && HitUI(g_toolbar_x+U(20),RiskBarY()+U(5)));
    Status("hello");UpdateStatusObjects(GetTickCount64());
    {int si=RegFind(UIS("T.StatusBG"));CHECK(si>=0 && g_reg[si].y==RiskBarY()+U(26));}    // the status line moves below the bar
    // The crosshair: the pointer is the stop, the size is shown before pressing.
    g_mouse_in=true;g_mouse_x=600;g_mouse_y=306;RiskPrepare();
    CHECK(!g_risk.active && g_rview.side==1 && std::fabs(g_rview.lots-0.47)<1e-12);
    g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
    CHECK(RowPieces(306,0,999)>20);                                                         // the dotted crosshair line
    // Press near the market, drag to 1.09800 (y 306), release.
    int x0=300,yst=306;
    BeginMouse(x0,300);CHECK(g_risk.active && g_rdrag==1);
    MoveMouse(x0+40,yst);EndMouse(x0+40,yst);
    CHECK(!g_risk.armed && g_risk.active && g_rdrag==0 && std::fabs(g_risk.stop-1.098)<1e-9);
    RiskPrepare();
    CHECK(g_rview.side==1 && g_rview.entry==1.1001 && std::fabs(g_rview.dist-0.0021)<1e-9);
    CHECK(std::fabs(g_rview.lots-0.47)<1e-12 && g_rview.flag==0 && std::fabs(g_rview.actual-98.7)<1e-6);  // 100 / 210 per lot, rounded down
    CHECK(g_rview.ntp==1 && std::fabs(g_rview.tp[0]-1.1043)<1e-9);                        // 2R
    CHECK(RiskEntryText()=="BUY 0.47 lots at market 1.10010");
    CHECK(RiskStopText()=="SL 1.09800  -21.0 pips  -98.70 USD (0.99%)");
    CHECK(RiskTargetText(1,0)=="TP1  2R  1.10430  +42.0 pips  +197.40 USD");
    // Drawn: stop and target lines; red and green areas behind the candles, from the press to the right.
    g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
    auto line_at=[&](int y,color col){for(auto& q:g_rects)if(!q.fill && q.y0<=y && y<=q.y1 && q.x1-q.x0>100 && (q.c&0xFFFFFF)==(uint)(col&0xFFFFFF))return true;return false;};
    CHECK(line_at(306,FPR_LOSS) && line_at(287,FPR_PROFIT));
    uint red=FillAt(x0+100,303),green=FillAt(x0+100,293);
    CHECK((red>>24)==41 && Near(red,RefARGB(FPR_LOSS,41)) && (green>>24)==33 && Near(green,RefARGB(FPR_PROFIT,33)));
    CHECK(FillAt(x0-20,303)==0);
    RiskGeometry();CHECK(RiskHit(x0+200,g_rgye)==0);                                       // a market entry is not draggable
    // The market moves: the entry follows the ask and the size follows the distance.
    g_syms["EURUSD"].bid=1.1001;g_syms["EURUSD"].ask=1.1002;g_dirty=false;g_rtick=GetTickCount64();
    RiskTick(GetTickCount64());CHECK(g_dirty);
    RiskPrepare();CHECK(g_rview.entry==1.1002 && std::fabs(g_rview.lots-0.45)<1e-12);      // 100 / 220
    // Drag the stop to 1.09900 (y 303): 100 / 120 -> 0.83 lots.
    BeginMouse(x0+200,306);CHECK(g_rdrag==1);MoveMouse(x0+200,303);EndMouse(x0+200,303);
    CHECK(std::fabs(g_risk.stop-1.099)<1e-9);RiskPrepare();CHECK(std::fabs(g_rview.lots-0.83)<1e-12);
    BeginMouse(x0+200,305);EndMouse(x0+200,305);CHECK(std::fabs(g_risk.stop-1.099)<1e-9);   // a plain click moves nothing
    // +TP adds the R multiples typed on the bar; repeats are refused; a bad list adds nothing.
    g_ui_dirty=true;BuildUI();
    ObjectSetString(0,UIS("K.R"),OBJPROP_TEXT,"3 4");Click(UIS("K.Add"));
    CHECK(g_risk.ntp==3 && g_risk.tp_r[1]==3 && g_risk.tp_r[2]==4 && g_rcfg.add_r=="3 4");
    Click(UIS("K.Add"));CHECK(g_risk.ntp==3);
    ObjectSetString(0,UIS("K.R"),OBJPROP_TEXT,"x");Click(UIS("K.Add"));CHECK(g_risk.ntp==3 && g_rcfg.add_r=="3 4");
    {FPRiskConfig saved;FPRDefaults(saved);CHECK(FPRReadFile("mem.risk",saved) && saved.add_r=="3 4");}
    // The green area reaches the farthest target; targets are numbered from the nearest.
    g_rects.clear();g_rec=true;g_dirty=true;Render();g_rec=false;
    CHECK(Near(FillAt(x0+100,287),RefARGB(FPR_PROFIT,33)));
    {string t1="",t3="";for(int i=0;i<g_rtag_n;i++){if(g_rtags[i].text.rfind("TP1 ",0)==0)t1=g_rtags[i].text;if(g_rtags[i].text.rfind("TP3 ",0)==0)t3=g_rtags[i].text;}
     CHECK(t1.find("  2R  ")!=string::npos && t3.find("  4R  ")!=string::npos);}
    // -TP removes the farthest target.
    RiskPrepare();Click(UIS("K.Del"));CHECK(g_risk.ntp==2 && g_risk.tp_r[1]==3);
    // A dragged target holds its price; the others still follow the stop.
    RiskPrepare();RiskGeometry();int ty=g_rgty[1];
    BeginMouse(x0+200,ty);CHECK(g_rdrag==11);MoveMouse(x0+200,ty-30);EndMouse(x0+200,ty-30);
    CHECK(!g_risk.tp_fixed[1] && std::fabs(g_risk.tp[1]-(1.2-(ty-30)/3000.0))<1e-5);
    double held=g_risk.tp[1],two=g_rview.tp[0];
    BeginMouse(x0+200,303);MoveMouse(x0+200,309);EndMouse(x0+200,309);RiskPrepare();
    CHECK(g_rview.tp[1]==held && g_rview.tp[0]!=two && std::fabs(g_rview.tp[0]-(g_rview.entry+2*g_rview.dist))<1e-9);
    // Esc while dragging puts the line back.
    double stop_before=g_risk.stop;BeginMouse(x0+200,309);MoveMouse(x0+200,330);
    {long lp=27;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);}
    CHECK(g_rdrag==0 && g_risk.stop==stop_before && g_risk.active);
    // Double-click a target line to remove it.
    RiskPrepare();RiskGeometry();ty=g_rgty[0];g_rlast_down=0;
    BeginMouse(x0+200,ty);EndMouse(x0+200,ty);g_fake_ticks+=100;BeginMouse(x0+200,ty);EndMouse(x0+200,ty);
    CHECK(g_risk.ntp==1 && !g_risk.tp_fixed[0]);
    // With New Fib armed, a press on a risk line starts the Fib instead.
    Arm();CHECK(g_armed && g_risk.active);
    RiskGeometry();{double keep_stop=g_risk.stop;BeginMouse(x0+200,g_rgys);CHECK(g_drag==1 && g_rdrag==0 && g_risk.stop==keep_stop);}
    CancelDrag();CHECK(!g_armed && g_count==0 && g_risk.active);
    // A press away from the box lines is not the risk tool's.
    CHECK(!RiskPress(x0+200,100) && !RiskPress(x0-50,309));
    // To a price of your own: the entry stays where the market is.
    RiskPrepare();double at=g_rview.entry;RiskSetMarket(false);CHECK(!g_risk.market && g_risk.entry==at && at==1.1002);
    RiskSetMarket(true);
    // Esc removes the measurement.
    {long lp=27;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);}
    CHECK(!g_risk.active && !g_risk.armed);
    // A price of your own: press at the entry, drag to the stop.
    RiskArm();g_ui_dirty=true;BuildUI();Click(UIS("K.Limit"));CHECK(!g_risk.market && g_rcfg.entry==1 && g_risk.armed);
    {FPRiskConfig saved;FPRDefaults(saved);CHECK(FPRReadFile("mem.risk",saved) && saved.entry==1);}   // remembered for next time
    int ye=315,ysl=321;   // 1.09500 and 1.09300
    BeginMouse(x0,ye);MoveMouse(x0,ysl);EndMouse(x0,ysl);
    CHECK(!g_risk.armed && g_risk.active && g_risk.entry==1.095 && std::fabs(g_risk.stop-1.093)<1e-9);
    RiskPrepare();CHECK(g_rview.side==1 && std::fabs(g_rview.lots-0.5)<1e-12 && RiskEntryText()=="BUY LIMIT 0.50 lots @ 1.09500");
    RiskGeometry();BeginMouse(x0+200,g_rgye);CHECK(g_rdrag==2);
    MoveMouse(x0+200,g_rgye-6);EndMouse(x0+200,g_rgye-6);CHECK(std::fabs(g_risk.entry-1.097)<1e-9);
    // ...or click the entry, then click the stop (it follows the pointer in between).
    RiskArm();CHECK(!g_risk.market && !g_risk.active);
    g_prev_down=false;BeginMouse(x0,ye);EndMouse(x0,ye);CHECK(g_risk.armed && g_risk.active && g_risk.stage==1 && g_status.find("Now click your stop")!=string::npos);
    HandlePointer(x0+50,ysl+3,false);CHECK(std::fabs(g_risk.stop-(1.2-(ysl+3)/3000.0))<1e-5);
    BeginMouse(x0+50,ysl);EndMouse(x0+50,ysl);CHECK(!g_risk.armed && std::fabs(g_risk.stop-1.093)<1e-9);
    // A sell above the market is a SELL LIMIT; at market the stop must be outside the spread.
    RiskArm();BeginMouse(x0,282);MoveMouse(x0,276);EndMouse(x0,276);RiskPrepare();          // 1.10600 -> 1.10800
    CHECK(g_rview.side==-1 && RiskEntryText().rfind("SELL LIMIT",0)==0);
    RiskSetMarket(true);RiskPrepare();CHECK(g_risk.market && g_rview.side==-1 && g_rview.entry==1.1001);
    // A risk too small for the minimum volume: no size, and what the minimum would lose.
    g_syms["EURUSD"].vmin=1.0;RiskRefreshValue();RiskPrepare();
    CHECK(g_rview.flag==1 && g_rview.lots==0 && RiskEntryText()=="SELL at market 1.10010: below 1.00 lot (1.00 loses 790.00 USD)");   // 79 pips
    g_syms["EURUSD"].vmin=0.01;RiskRefreshValue();
    g_syms["EURUSD"].bid=1.1000;g_syms["EURUSD"].ask=1.1010;
    RiskArm();BeginMouse(x0,299);EndMouse(x0,299);CHECK(g_risk.armed && !g_risk.active);  // inside the spread: try again
    // The toolbar button toggles a measurement being made; so does the shortcut.
    g_ui_dirty=true;BuildUI();Click(UIS("T.Risk"));CHECK(!g_risk.armed);Click(UIS("T.Risk"));CHECK(g_risk.armed);
    g_risk_ctrl=false;g_risk_shift=false;g_risk_key_held=false;
    {long lp='R';double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(!g_risk.armed);OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(!g_risk.armed);
     OnChartEvent(CHARTEVENT_KEYUP,lp,dp,sp);OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(g_risk.armed);OnChartEvent(CHARTEVENT_KEYUP,lp,dp,sp);}
    g_risk_ctrl=true;g_risk_shift=true;
    // New Fib drops a measurement being made.
    Arm();CHECK(g_armed && !g_risk.armed);CancelDrag();
    // ---- the Risk window: modes, commission, targets, your own value (per pip on forex)
    RiskArm();OpenRisk();CHECK(g_reditor);g_ui_dirty=true;BuildUI();
    CHECK(RegFind(UIS("W.Mode0"))>=0 && RegFind(UIS("W.Amount"))>=0 && RegFind(UIS("W.Value"))>=0 && RegFind(UIS("W.OK"))>=0 && RegFind(UIS("K.Risk"))>=0);
    CHECK(HitUI(g_panel_x+U(20),g_panel_y+U(300)) && g_texts[UIS("W.Used")].find("contract size and tick value agree")!=string::npos);
    RiskPanelClick("Mode1");CHECK(g_redit.mode==1);g_ui_dirty=true;BuildUI();
    ObjectSetString(0,UIS("W.Percent"),OBJPROP_TEXT,"0.5");ObjectSetString(0,UIS("W.Comm"),OBJPROP_TEXT,"7");
    ObjectSetString(0,UIS("W.Targets"),OBJPROP_TEXT,"3 1");ObjectSetString(0,UIS("W.Value"),OBJPROP_TEXT,"10");   // 10 USD per pip
    CHECK(HarvestRiskEdits() && g_redit.percent==0.5 && FPRCommission(g_redit,"EURUSD")==7 && g_redit.targets=="1 3");
    CHECK(std::fabs(FPRManual(g_redit,"EURUSD")-100000)<1e-6);
    ObjectSetString(0,UIS("W.Percent"),OBJPROP_TEXT,"150");CHECK(!HarvestRiskEdits() && g_redit.percent==0.5);
    g_ui_dirty=true;BuildUI();CHECK(g_texts[UIS("W.Percent")]=="0.5" && g_texts[UIS("W.Used")].find("your own value")!=string::npos);
    // The chart previews the window: 0.5% of 10,000 = 50, 20 pips + 7 commission = 207 per lot -> 0.24.
    BeginMouse(700,300);MoveMouse(700,303);EndMouse(700,303);RiskPrepare();
    CHECK(!g_risk.armed && std::fabs(g_rview.dist-0.002)<1e-9 && std::fabs(g_rview.lots-0.24)<1e-12 && std::fabs(g_rview.actual-49.68)<1e-6);
    CHECK(g_rview.ntp==2 && std::fabs(g_rview.tp_r[0]-1)<1e-12);                          // the window's targets: 1R and 3R
    CHECK(RiskStopText()=="SL 1.09900  -20.0 pips  -49.68 USD (0.50%)" && RiskTargetText(1,0)=="TP1  1R  1.10300  +20.0 pips  +46.32 USD");
    RiskPanelClick("UseTick");CHECK(std::fabs(FPRManual(g_redit,"EURUSD")-100000)<1e-6);
    RiskPanelClick("ClearValue");CHECK(FPRManual(g_redit,"EURUSD")==0 && FPRCommission(g_redit,"EURUSD")==7);
    RiskPanelClick("Cancel");CHECK(!g_reditor && g_rcfg.mode==0);
    RiskPrepare();CHECK(std::fabs(g_rview.lots-0.5)<1e-12);                               // back to 100 USD, no commission
    // OK keeps it, for every chart of this account.
    OpenRisk();RiskPanelClick("Mode1");g_ui_dirty=true;BuildUI();
    ObjectSetString(0,UIS("W.Percent"),OBJPROP_TEXT,"0.5");ObjectSetString(0,UIS("W.Comm"),OBJPROP_TEXT,"7");
    RiskPanelClick("OK");CHECK(!g_reditor && g_rcfg.mode==1 && g_rcfg.percent==0.5 && FPRCommission(g_rcfg,"EURUSD")==7);
    {FPRiskConfig back;FPRDefaults(back);CHECK(FPRReadFile("mem.risk",back) && back.mode==1 && back.percent==0.5 && FPRCommission(back,"EURUSD")==7);}
    // One window at a time; Esc closes the innermost thing first.
    g_count=1;MakeFib(g_sets[0],90,"Fib",false,PERIOD_H1);g_selected=0;
    OpenRisk();OpenEditor();CHECK(!g_editor && g_reditor);OpenZones();CHECK(!g_zeditor);CloseRisk();
    RiskArm();OpenZones();CHECK(g_zeditor && g_risk.armed);
    {long lp=27;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(!g_risk.armed && g_zeditor);
     OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(!g_zeditor);}
    g_count=0;g_selected=-1;RiskClear();g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("K.Market"))<0);   // the bar goes with the measurement
    g_zact.enabled=true;g_zcfg.enabled=true;
   }

   // ==== 1.67: price points
   {
    g_zact.enabled=false;g_zact.broker_mode=1;g_zact.broker_gmt=2;ZoneResolveBroker();
    CHECK(g_zmode==1 && g_zgmt==2);
    g_owner=true;g_hidden=false;g_editor=false;g_zeditor=false;g_reditor=false;g_list=false;g_popup=0;g_count=0;g_selected=-1;
    g_width=1000;g_height=600;g_tf=4;g_cull_ok=false;g_view_scale=0;g_view_max=1.2;
    // ---- the default list: all 55 ICT price points in 30 rows; the sessions and NDOG switched on
    FPPointConfig pc;FPPDefaults(pc);
    CHECK(pc.count==30 && pc.enabled && pc.end_taken && pc.taken_show==0 && pc.week_open==0 && pc.days_back==10);
    {int levels=0;string on="";bool ok=true;
     for(int i=0;i<pc.count;i++)
       {
        int k=pc.rows[i].kind;
        levels+=k==FPPK_GAP?(pc.rows[i].sub==2?0:3):(k==FPPK_WINDOW?2:(k==FPPK_PERIOD?4:1));   // NWOG is the one addition
        if(pc.rows[i].enabled)on+=pc.rows[i].name+",";
        ok=ok && pc.rows[i].uid==(uint)(i+1) && (pc.rows[i].parts&~FPPAllowed(k))==0 && pc.rows[i].parts!=0;
       }
     CHECK(levels==55 && on=="NDOG,Asia,London,New York," && ok);}
    int org=FindRow(pc,"ORG"),ndog=FindRow(pc,"NDOG"),nwog=FindRow(pc,"NWOG"),asia=FindRow(pc,"Asia"),lon=FindRow(pc,"London"),nys=FindRow(pc,"New York");
    int mno=FindRow(pc,"Midnight open"),fvg=FindRow(pc,"NY FPFVG AM"),obam=FindRow(pc,"NY FPOB AM"),obpm=FindRow(pc,"NY FPOB PM");
    int day=FindRow(pc,"Day"),week=FindRow(pc,"Week"),month=FindRow(pc,"Month");
    CHECK(org==0 && ndog==1 && nwog==2 && asia==24 && lon==25 && nys==26 && mno==8 && fvg==18 && obam==19 && obpm==23 && day==27 && week==28 && month==29);
    CHECK(FPPPartName(pc.rows[lon],0)=="LSH" && FPPPartName(pc.rows[lon],1)=="LSL" && FPPPartName(pc.rows[lon],2)=="London CE");
    CHECK(FPPPartName(pc.rows[day],0)=="HOD" && FPPPartName(pc.rows[day],4)=="OOD" && FPPPartName(pc.rows[week],5)=="COW" && FPPPartName(pc.rows[month],1)=="LOM");
    CHECK(FPPPartName(pc.rows[ndog],4)=="NDOG open" && FPPPartName(pc.rows[ndog],5)=="NDOG close" && FPPPartName(pc.rows[mno],4)=="MNO");
    CHECK(FPPPartName(pc.rows[fvg],0)=="NY FPFVG AM top" && FPPPartName(pc.rows[fvg],3)=="NY FPFVG AM" && FPPPartName(pc.rows[fvg],2)=="NY FPFVG AM CE");
    CHECK(pc.rows[asia].start==1140 && pc.rows[asia].end==240 && pc.rows[asia].ink==clrMediumPurple && pc.rows[ndog].ink==clrHotPink && pc.rows[obpm].start==810);

    // ---- settings file: verified on save; damaged or impossible files refused
    CHECK(FPPWriteFile("t.points",pc));
    {FPPointConfig r;CHECK(FPPReadFile("t.points",r) && r.count==30 && r.rows[ndog].name=="NDOG" && r.rows[ndog].enabled && r.rows[ndog].uid==2 && r.week_open==0 && r.end_taken && r.group_tf[5]==19);}
    {FPPointConfig bad=pc;bad.rows[asia].parts|=FPPP_O;CHECK(!FPPWriteFile("bad.points",bad));}    // a part a window does not have
    {FPPointConfig bad=pc;bad.rows[5].uid=bad.rows[4].uid;CHECK(!FPPWriteFile("bad.points",bad));} // two rows, one identity
    {FPPointConfig bad=pc;bad.weeks_back=27;CHECK(!FPPWriteFile("bad.points",bad));}
    g_disk["long.points"]=g_disk["t.points"]+"x";{FPPointConfig r;CHECK(!FPPReadFile("long.points",r));}
    g_disk["cut.points"]=g_disk["t.points"].substr(0,200);{FPPointConfig r;r.count=-5;CHECK(!FPPReadFile("cut.points",r) && r.count==-5);}

    // ---- windows on the broker's clock
    long dfri=FPDaysFromCivil(2026,11,13),dmon=dfri+3,dtue=dfri+4;
    datetime ts=0,te=0;
    CHECK(FPPWindow(pc.rows[asia],dtue,0,1,2,ts,te) && ts==SV(2026,11,16,19,0) && te==SV(2026,11,17,4,0));
    CHECK(FPPWindow(pc.rows[ndog],dtue,0,1,2,ts,te) && ts==SV(2026,11,16,16,59) && te==SV(2026,11,16,17,0));
    CHECK(!FPPWindow(pc.rows[ndog],dmon,0,1,2,ts,te));                                          // Monday's gap is the NWOG
    CHECK(FPPWindow(pc.rows[org],dmon,0,1,2,ts,te) && ts==SV(2026,11,13,16,14) && te==SV(2026,11,16,9,30));
    CHECK(FPPWindow(pc.rows[nwog],dmon,0,1,2,ts,te) && ts==SV(2026,11,13,16,59) && te==SV(2026,11,15,0,0));
    CHECK(FPPWindow(pc.rows[nwog],dmon,1,1,2,ts,te) && te==(datetime)(dmon*86400));             // Monday 00:00, server clock
    CHECK(FPPWindow(pc.rows[day],dtue,0,1,2,ts,te) && ts==SV(2026,11,16,17,0) && te==SV(2026,11,17,17,0));
    CHECK(FPPWindow(pc.rows[week],dmon,0,1,2,ts,te) && ts==SV(2026,11,15,0,0) && te==SV(2026,11,20,17,0));
    CHECK(FPPWindow(pc.rows[week],dmon,1,1,2,ts,te) && ts==(datetime)(dmon*86400) && te==SV(2026,11,20,17,0));
    CHECK(FPPWindow(pc.rows[month],2026*12+10,0,1,2,ts,te) && ts==SV(2026,10,31,17,0) && te==SV(2026,11,30,17,0));
    CHECK(FPPWindow(pc.rows[fvg],dtue,0,1,2,ts,te) && ts==SV(2026,11,17,9,30) && te==SV(2026,11,17,10,0));
    // GMT+2 with EU daylight saving in the week the clocks disagree: London starts an hour earlier on it.
    CHECK(FPPWindow(pc.rows[lon],FPDaysFromCivil(2026,10,27),0,3,2,ts,te) && ts==(datetime)NY(2026,10,27,9,0));
    CHECK(FPPWindow(pc.rows[lon],dtue,0,3,2,ts,te) && ts==(datetime)NY(2026,11,17,10,0));
    // GMT+0: the week's open is searched from Sunday 00:00 New York, or from Monday 00:00 on the server.
    CHECK(FPPWindow(pc.rows[nwog],dmon,0,2,0,ts,te) && te==(datetime)NY(2026,11,15,5,0));
    CHECK(FPPWindow(pc.rows[nwog],dmon,1,2,0,ts,te) && te==(datetime)(dmon*86400));
    CHECK(FPPWeekOf(dtue)==dmon && FPPWeekOf(dfri+1)==dmon-7 && FPPWeekOf(dfri+2)==dmon-7 && FPPMonthOf(dtue)==2026*12+10);

    // ---- occurrences: trading days back (weekends skipped), weeks and months back
    g_test_now=SV(2026,11,17,14,0);PPMakeBars(g_test_now);
    g_pcfg=pc;g_pcfg.days_back=3;g_pcfg.weeks_back=2;g_pcfg.months_back=3;
    for(int i=0;i<g_pcfg.count;i++)g_pcfg.rows[i].enabled=true;
    g_pact=g_pcfg;g_peditor=false;PPBuild();
    CHECK(OccCount(lon)==3 && OccOf(lon,dtue)>=0 && OccOf(lon,dmon)>=0 && OccOf(lon,dfri)>=0);
    CHECK(OccCount(ndog)==2 && OccOf(ndog,dmon)<0 && OccCount(nwog)==2 && OccOf(nwog,dmon)>=0 && OccOf(nwog,dmon-7)>=0);
    CHECK(OccCount(week)==2 && OccCount(month)==3 && OccOf(month,2026*12+10)>=0 && OccOf(month,2026*12+8)>=0 && OccCount(day)==3);
    {bool future=false;for(int i=0;i<g_pocc_n;i++)if(g_pocc[i].future)future=true;CHECK(!future);}
    g_pact.rows[lon].sample=1;PPBuild();CHECK(OccCount(lon)==2 && OccOf(lon,dmon)>=0 && OccOf(lon,dmon-7)>=0);   // Mondays only
    g_pact.rows[lon].sample=0;PPBuild();

    // ---- prices from M1 (H1 for periods, refined to the minute)
    for(int i=0;i<g_pocc_n;i++)PPRead(i,g_test_now);
    int a=OccOf(asia,dtue),l=OccOf(lon,dtue),ny=OccOf(nys,dtue),nd=OccOf(ndog,dtue),og=OccOf(org,dtue),om=OccOf(org,dmon),nw=OccOf(nwog,dmon);
    int mo=OccOf(mno,dtue),fv=OccOf(fvg,dtue),oa=OccOf(obam,dtue),op=OccOf(obpm,dtue),dt=OccOf(day,dtue),dm=OccOf(day,dmon),wk=OccOf(week,dmon),lf=OccOf(lon,dfri);
    CHECK(g_pocc[a].state==1 && g_pocc[a].hi==1.1001 && g_pocc[a].th==SV(2026,11,16,19,0) && g_pocc[a].lo==1.0999 && g_pocc[a].formed==SV(2026,11,17,4,0));
    CHECK(g_pocc[l].state==1 && !g_pocc[l].live && g_pocc[l].hi==1.1050 && g_pocc[l].th==SV(2026,11,17,5,12) && g_pocc[l].lo==1.0950 && g_pocc[l].tl==SV(2026,11,17,9,47));
    CHECK(g_pocc[ny].state==1 && g_pocc[ny].live && g_pocc[ny].hi==1.1051 && g_pocc[ny].th==SV(2026,11,17,13,5));          // live: so far
    CHECK(g_pocc[nd].state==1 && g_pocc[nd].cl==1.1 && g_pocc[nd].tc==SV(2026,11,16,16,59) && g_pocc[nd].op==1.1010 && g_pocc[nd].to==SV(2026,11,16,18,0) && g_pocc[nd].dir==1);
    CHECK(g_pocc[OccOf(ndog,dfri)].state==2);                                                                       // no Thursday close in the data
    CHECK(g_pocc[og].dir==1 && g_pocc[og].op==1.1020 && g_pocc[og].tc==SV(2026,11,16,16,14) && g_pocc[om].tc==SV(2026,11,13,16,14) && g_pocc[om].dir==0);
    CHECK(g_pocc[nw].dir==-1 && g_pocc[nw].cl==1.1 && g_pocc[nw].tc==SV(2026,11,13,16,59) && g_pocc[nw].op==1.0990 && g_pocc[nw].to==SV(2026,11,15,18,0));
    CHECK(g_pocc[mo].op==1.1 && g_pocc[mo].to==SV(2026,11,17,0,0));
    CHECK(g_pocc[fv].state==1 && g_pocc[fv].dir==-1 && g_pocc[fv].hi==1.1018 && g_pocc[fv].lo==1.1001 && g_pocc[fv].th==SV(2026,11,17,9,30) && g_pocc[fv].formed==SV(2026,11,17,9,33));
    CHECK(g_pocc[oa].state==2);                                                                                     // no break of structure in the window
    CHECK(g_pocc[op].state==1 && g_pocc[op].dir==1 && g_pocc[op].hi==1.1001 && g_pocc[op].lo==1.0998 && g_pocc[op].th==SV(2026,11,17,13,39) && g_pocc[op].formed==SV(2026,11,17,13,42));
    CHECK(g_pocc[dt].live && g_pocc[dt].hi==1.1051 && g_pocc[dt].th==SV(2026,11,17,13,5) && g_pocc[dt].op==1.1010 && g_pocc[dt].to==SV(2026,11,16,18,0));
    CHECK(!g_pocc[dm].live && g_pocc[dm].hi==1.1030 && g_pocc[dm].th==SV(2026,11,16,10,23) && g_pocc[dm].lo==1.0988 && g_pocc[dm].tl==SV(2026,11,15,18,0) && g_pocc[dm].cl==1.1);
    CHECK(g_pocc[wk].live && g_pocc[wk].op==1.0990 && g_pocc[wk].hi==1.1051 && g_pocc[wk].lo==1.0950);
    CHECK(g_pocc[OccOf(month,2026*12+9)].state==2);

    // ---- taken: the first candle after a level formed that trades through it
    PPScanAll(g_test_now);
    CHECK(g_pocc[a].tk[0]==SV(2026,11,17,5,12) && g_pocc[a].tk[1]==SV(2026,11,17,9,47) && g_pocc[a].tk[2]==SV(2026,11,17,4,0));
    CHECK(g_pocc[l].tk[0]==SV(2026,11,17,13,5) && g_pocc[l].tk[1]==0 && g_pocc[l].tk[2]==SV(2026,11,17,12,0));    // 12:30 only touched it
    CHECK(g_pocc[ny].tk[0]==0 && g_pocc[ny].scan_to==0);                                                           // live: nothing taken yet
    CHECK(g_pocc[nd].tk[2]==SV(2026,11,16,18,1) && g_pocc[nd].tk[5]==SV(2026,11,16,18,2) && g_pocc[nd].tk[3]==g_pocc[nd].tk[5]);   // CE, then filled
    CHECK(g_pocc[nd].tk[4]==SV(2026,11,17,5,12));                                                                  // the open: once price came back
    CHECK(g_pocc[og].tk[5]==SV(2026,11,17,9,31) && g_pocc[og].tk[2]==SV(2026,11,17,9,31) && g_pocc[og].tk[4]==SV(2026,11,17,12,30));
    CHECK(g_pocc[nw].tk[5]==SV(2026,11,15,18,1) && g_pocc[nw].tk[2]==SV(2026,11,15,18,1) && g_pocc[nw].tk[4]==SV(2026,11,17,9,47));
    CHECK(g_pocc[mo].tk[4]==SV(2026,11,17,9,31));
    CHECK(g_pocc[fv].tk[1]==SV(2026,11,17,9,33) && g_pocc[fv].tk[2]==SV(2026,11,17,12,30) && g_pocc[fv].tk[0]==SV(2026,11,17,12,30) && g_pocc[fv].tk[3]==g_pocc[fv].tk[0]);
    CHECK(g_pocc[op].tk[0]==SV(2026,11,17,13,42) && g_pocc[op].tk[1]==0 && g_pocc[op].tk[3]==0);                  // entered, not filled
    CHECK(g_pocc[dm].tk[0]==SV(2026,11,17,5,12) && g_pocc[dm].tk[1]==SV(2026,11,17,9,47) && g_pocc[dm].tk[5]==SV(2026,11,16,18,2) && g_pocc[dm].tk[2]==SV(2026,11,16,18,0) && g_pocc[dm].tk[4]==SV(2026,11,17,9,47));
    CHECK(g_pocc[lf].tk[0]==SV(2026,11,16,10,23) && g_pocc[lf].tk[1]==SV(2026,11,15,18,0) && g_pocc[lf].tk[2]==SV(2026,11,13,12,0));
    // Friday's close: minute candles across the weekend, so the Sunday open leaving it and coming back counts.
    CHECK(g_pocc[OccOf(day,dfri)].tk[5]==SV(2026,11,15,18,1));
    // Friday's NY AM opening range: three days on, hourly candles, each hit found again to the minute.
    {int orf=OccOf(FindRow(pc,"NY AM OR"),dfri);CHECK(orf>=0 && g_pocc[orf].tk[0]==SV(2026,11,16,10,23) && g_pocc[orf].tk[1]==SV(2026,11,15,18,0));}
    // The midnight open is the first candle at or after 00:00, never the one before.
    {std::vector<MqlRates> keep=g_bars;
     g_bars.erase(std::remove_if(g_bars.begin(),g_bars.end(),[](const MqlRates& b){return b.time>=SV(2026,11,17,0,0) && b.time<SV(2026,11,17,0,3);}),g_bars.end());
     PPSetBar(2026,11,17,0,3,1.1003,1.1004,1.1002,1.1003);
     g_pocc[mo].state=0;PPRead(mo,g_test_now);CHECK(g_pocc[mo].op==1.1003 && g_pocc[mo].to==SV(2026,11,17,0,3));
     g_bars=keep;g_pocc[mo].state=0;PPRead(mo,g_test_now);PPScanAll(g_test_now);CHECK(g_pocc[mo].op==1.1);}
    // The ORG close is its session day's own close: with Friday a holiday, Thursday's 16:14 candle, not Thursday's last.
    {std::vector<MqlRates> keep=g_bars;
     g_bars.clear();
     for(int m=0;m<60;m++){MqlRates r{};r.time=SV(2026,11,12,16,m);r.open=1.1;r.close=m==14?1.0977:1.1;r.high=1.1001;r.low=1.0970;g_bars.push_back(r);}
     for(const MqlRates& b:keep)if(b.time>=SV(2026,11,15,18,0))g_bars.push_back(b);
     g_pocc[om].state=0;PPRead(om,g_test_now);
     CHECK(g_pocc[om].state==1 && g_pocc[om].cl==1.0977 && g_pocc[om].tc==SV(2026,11,12,16,14));
     g_bars=keep;g_pocc[om].state=0;PPRead(om,g_test_now);CHECK(g_pocc[om].tc==SV(2026,11,13,16,14));}
    // A Friday close that Sunday's open leaves and comes back to within its first hour, with nothing else taken
    // in that hour: found because the first three days are read in minutes.
    {std::vector<MqlRates> keep=g_bars;
     PPSetBar(2026,11,13,9,0,1.1020,1.1020,1.0999,1.1);PPSetBar(2026,11,13,13,0,1.1,1.1100,1.0999,1.1);PPSetBar(2026,11,13,14,0,1.1,1.1001,1.0950,1.1);
     int df=OccOf(day,dfri);g_pocc[df].state=0;PPRead(df,g_test_now);PPScanAll(g_test_now);
     CHECK(g_pocc[df].hi==1.1100 && g_pocc[df].lo==1.0950 && g_pocc[df].op==1.1020 && g_pocc[df].tk[5]==SV(2026,11,15,18,1) && g_pocc[df].tk[0]==0 && g_pocc[df].tk[1]==0);
     CHECK(g_pocc[df].tk[4]==SV(2026,11,16,10,23));
     g_bars=keep;g_pocc[df].state=0;PPRead(df,g_test_now);PPScanAll(g_test_now);CHECK(g_pocc[df].tk[5]==SV(2026,11,15,18,1));}
    // New prices (a corrected candle) start the scan again.
    PPSetBar(2026,11,17,6,0,1.1,1.1055,1.0999,1.1);PPRead(l,g_test_now);
    CHECK(g_pocc[l].hi==1.1055 && g_pocc[l].tk[0]==0 && g_pocc[l].scan_to==0);
    PPSetBar(2026,11,17,6,0,1.1,1.1001,1.0999,1.1);g_pocc[l].state=0;PPRead(l,g_test_now);PPScanAll(g_test_now);CHECK(g_pocc[l].tk[0]==SV(2026,11,17,13,5));
    // A colour change keeps what was read; a new start time reads again.
    {datetime t0=g_pocc[l].tk[0];g_pact.rows[lon].ink=clrRed;PPBuild();int l2=OccOf(lon,dtue);
     CHECK(l2>=0 && g_pocc[l2].state==1 && g_pocc[l2].tk[0]==t0);
     g_pact.rows[lon].start=240;PPBuild();l2=OccOf(lon,dtue);CHECK(g_pocc[l2].state==0 && g_pocc[l2].ts==SV(2026,11,17,4,0));}
    // A changed week open moves the NWOG's open search: read again, not reused.
    {int w0=OccOf(nwog,dmon);CHECK(w0>=0 && g_pocc[w0].state==1);
     g_pact.week_open=1;PPBuild();int w1=OccOf(nwog,dmon);CHECK(w1>=0 && g_pocc[w1].state==0 && g_pocc[w1].te==(datetime)(dmon*86400));
     g_pact.week_open=0;PPBuild();}

    // ---- on the chart: lines end where price takes them; zones shaded; labels; arrows
    g_pcfg=pc;g_pcfg.days_back=3;g_pcfg.weeks_back=2;g_pcfg.rows[fvg].enabled=true;g_pact=g_pcfg;g_pocc_dirty=true;
    g_xy_t0=SV(2026,11,17,0,0);
    for(int f=0;f<40;f++){g_dirty=true;Render();}
    l=OccOf(lon,dtue);a=OccOf(asia,dtue);ny=OccOf(nys,dtue);fv=OccOf(fvg,dtue);nd=OccOf(ndog,dtue);
    CHECK(l>=0 && a>=0 && ny>=0 && fv>=0 && nd>=0);
    {int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x0==312 && g_ppline[k].x1==785 && g_ppline[k].y==285 && g_ppline[k].alpha==90 && g_ppline[k].style==STYLE_DASHDOTDOT && g_ppline[k].taken);}
    {int k=LineOf(l,1);CHECK(k>=0 && g_ppline[k].x0==587 && g_ppline[k].x1==999 && g_ppline[k].y==315 && g_ppline[k].alpha==255 && g_ppline[k].style==STYLE_DASHDOT && !g_ppline[k].taken);}
    CHECK(LineOf(l,2)<0);                                                                                           // CE is not one of London's parts
    {int k=LineOf(ny,0);CHECK(k>=0 && g_ppline[k].x0==785 && g_ppline[k].x1==999);}                              // live: to the right edge
    {int k=LineOf(nd,4);CHECK(k>=0 && g_ppline[k].x0==-360 && g_ppline[k].x1==312 && g_ppline[k].alpha==90 && g_ppline[k].style==STYLE_SOLID);}
    CHECK(LineOf(nd,5)<0);                                                                                          // taken off screen, left of the chart
    {int b=-1;for(int k=0;k<g_ppbox_n;k++)if(g_ppbox[k].occ==fv)b=k;
     CHECK(b>=0 && g_ppbox[b].zone && g_ppbox[b].x0==570 && g_ppbox[b].x1==750 && g_ppbox[b].y0==295 && g_ppbox[b].y1==300);
     bool found=false;
     for(int k=0;k<g_ppfill_n;k++)
        if(g_ppfill[k].x0==570 && g_ppfill[k].x1==750 && g_ppfill[k].kind==2 && std::fabs(g_ppfill[k].a0-0.14*0.4)<1e-9 && g_ppfill[k].ink==FPBlend(clrMediumSeaGreen,clrBlack,0.3))found=true;
     CHECK(found && g_ppfill_sig!=0);}                                                                              // filled: faint; an FVG a darker shade
    {g_rec=true;g_rects.clear();g_fill_sig=0;g_dirty=true;Render();g_rec=false;
     uint c=FillAt(660,297);CHECK(((c>>24)&255)>=13 && ((c>>24)&255)<=15);}                                       // on the background canvas
    {ulong before=g_fill_sig;g_pact.fill=false;g_dirty=true;Render();CHECK(g_fill_sig!=before && g_ppfill_n==0);g_pact.fill=true;g_dirty=true;Render();}  // redrawn when only they change
    g_pact.end_taken=false;g_dirty=true;Render();{int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x1==999 && g_ppline[k].alpha==255 && !g_ppline[k].taken);}
    g_pact.end_taken=true;g_pact.rows[lon].ends=2;g_dirty=true;Render();{int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x1==999);}          // this row runs on
    g_pact.rows[lon].ends=0;g_pact.taken_show=1;g_dirty=true;Render();CHECK(LineOf(l,0)<0 && LineOf(l,1)>=0);                           // hidden once taken
    g_pact.taken_show=2;g_dirty=true;Render();{int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x1==785 && g_ppline[k].alpha==255);}          // kept as set
    g_pact.taken_show=0;g_pact.end_taken=false;g_pact.rows[lon].ends=1;g_dirty=true;Render();{int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x1==785);}  // on its own
    g_pact.end_taken=true;g_pact.rows[lon].ends=0;
    // Labels: names at the line ends; per row or for all; merged at one price; stacked, never overlapping.
    g_dirty=true;Render();
    CHECK(LabelWith("LSH")>=0 && LabelWith("LSL")>=0 && LabelWith("NY FPFVG AM "+Glyph(0x25BC))>=0 && LabelWith("NY FPFVG AM CE")<0);
    {int k=LabelWith("LSH");CHECK(g_pplabel[k].x==785-18-4 && g_pplabel[k].y==285-14-1);}
    g_pact.label_mode=2;g_dirty=true;Render();CHECK(LabelWith("LSH 1.10500")>=0);
    g_pact.label_mode=1;g_dirty=true;Render();CHECK(LabelWith("LSH Tue 17")>=0);
    g_pact.label_mode=3;g_dirty=true;Render();CHECK(g_pplabel_n==0);
    g_pact.label_mode=0;g_pact.rows[lon].label=3;g_dirty=true;Render();CHECK(LabelWith("LSH 1.10500")>=0 && LabelWith("NYH 1.")<0);
    g_pact.rows[lon].label=0;
    g_pact.rows[lon].ends=2;g_dirty=true;Render();{int m=LabelWith("LSH / NYH");CHECK(m>=0 && LabelWith("NYH")==m);}
    g_pact.merge=false;g_dirty=true;Render();
    {int a1=LabelWith("LSH"),b1=LabelWith("NYH");CHECK(a1>=0 && b1>=0 && a1!=b1 && (g_pplabel[a1].y+14<=g_pplabel[b1].y || g_pplabel[b1].y+14<=g_pplabel[a1].y));
     bool clear=true;
     for(int p=0;p<g_pplabel_n;p++)for(int q=p+1;q<g_pplabel_n;q++)
       {
        if(g_pplabel[p].w==0 || g_pplabel[q].w==0)continue;
        bool xo=!(g_pplabel[p].x>g_pplabel[q].x+g_pplabel[q].w+2 || g_pplabel[q].x>g_pplabel[p].x+g_pplabel[p].w+2);
        bool yo=!(g_pplabel[p].y>=g_pplabel[q].y+g_pplabel[q].h || g_pplabel[q].y>=g_pplabel[p].y+g_pplabel[p].h);
        if(xo && yo)clear=false;
       }
     CHECK(clear);}
    g_pact.merge=true;g_pact.rows[lon].ends=0;
    // Ray back (row default) and names pinned at the left edge.
    g_pact.rows[lon].ray=true;g_pact.pin_left=true;g_dirty=true;Render();
    {int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].x0==0);int p=-1;for(int q=0;q<g_pplabel_n;q++)if(g_pplabel[q].w>0 && g_pplabel[q].x==4 && g_pplabel[q].text=="LSH")p=q;CHECK(p>=0);}
    g_pact.rows[lon].ray=false;g_pact.pin_left=false;
    // Below the visible prices: an arrow at the edge, unless switched off.
    g_height=280;g_dirty=true;Render();
    {bool below=false,taken=false;for(int k=0;k<g_ppoff_n;k++){if(g_ppoff[k].occ==l && g_ppoff[k].part==1 && g_ppoff[k].y==315)below=true;if(g_ppoff[k].occ==l && g_ppoff[k].part==0)taken=true;}
     CHECK(below && !taken);}                                                                                       // a taken level gets no arrow
    g_pact.offscreen=false;g_dirty=true;Render();CHECK(g_ppoff_n==0);
    g_pact.offscreen=true;g_height=600;g_dirty=true;Render();
    // ---- hover: what it is, its price, when it formed and whether it was taken
    {int occ=-1,part=-1;CHECK(FindPPAt(500,286,occ,part) && occ==l && part==0);
     MQLArr<string> lines;color accent=clrNONE;PPTip(occ,part,lines,accent);
     std::vector<string> v(lines.v.begin(),lines.v.end());
     CHECK(lines[0]=="LSH" && PPHasLine(v,"Price\t1.10500") && PPHasLine(v,"Status\tTaken Tue 13:05 New York") && PPHasLine(v,"Formed\tTue 05:12 New York") && accent==clrRoyalBlue);}
    g_pact.rows[fvg].parts=FPPP_BOX;g_dirty=true;Render();
    {int occ=-1,part=-1;CHECK(FindPPAt(660,297,occ,part) && occ==fv && part==3);
     MQLArr<string> lines;color accent=clrNONE;PPTip(occ,part,lines,accent);std::vector<string> v(lines.v.begin(),lines.v.end());
     CHECK(lines[0]=="NY FPFVG AM "+Glyph(0x25BC) && PPHasLine(v,"Top\t1.10180") && PPHasLine(v,"Bottom\t1.10010") && PPHasLine(v,"Status\tFilled Tue 12:30 New York"));}
    g_pact.rows[fvg].parts=FPPP_BOX|FPPP_CE;g_dirty=true;Render();

    // ---- select one: ray it back or hide it on this chart, or open its row
    g_pflag_store="mem.pts";g_disk.erase("mem.pts");g_pflag_n=0;
    CHECK(PPPress(500,285) && g_psel_uid==g_pact.rows[lon].uid && g_psel_key==dtue && g_psel_part==0);
    g_dirty=true;Render();CHECK(g_psel==l);
    g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("X.Ray"))>=0 && RegFind(UIS("X.Hide"))>=0 && RegFind(UIS("X.Row"))>=0 && HitUI(g_pchip_x+5,g_pchip_y+5));
    {int k=LineOf(l,0);CHECK(k>=0 && g_ppline[k].sel && g_ppline[k].width==2 && g_ppline[k].alpha==255);}      // selected: thicker, full strength
    PPChipClick("Ray");g_dirty=true;Render();
    CHECK(g_pflag_n==1 && g_pflags[0].flags==1 && g_disk.count("mem.pts")==1 && g_ppline[LineOf(l,0)].x0==0 && g_ppline[LineOf(l,1)].x0==0);
    CHECK(LineOf(OccOf(lon,dmon),0)>=0 && g_ppline[LineOf(OccOf(lon,dmon),0)].x0<0);                               // only that day's London
    PPChipClick("Ray");g_dirty=true;Render();CHECK(g_pflag_n==0 && g_ppline[LineOf(l,0)].x0==312);
    g_pact.rows[lon].ray=true;PPChipClick("Ray");CHECK(g_pflag_n==1 && g_pflags[0].flags==2);g_dirty=true;Render();  // the row rays; this day not
    CHECK(g_ppline[LineOf(l,0)].x0==312 && FPPRay(g_pocc[OccOf(lon,dmon)],g_pact.rows[lon]) && !FPPRay(g_pocc[l],g_pact.rows[lon]));
    PPChipClick("Ray");CHECK(g_pflag_n==0);g_pact.rows[lon].ray=false;
    PPChipClick("Hide");g_dirty=true;Render();
    CHECK(g_psel_uid==0 && LineOf(l,0)<0 && LineOf(l,1)<0 && PPHiddenCount(g_pact.rows[lon].uid)==1);
    g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("X.Ray"))<0);
    PPLoadFlags();CHECK(g_pflag_n==1 && g_pflags[0].key==dtue && g_pflags[0].flags==4);                            // read back from the file
    PPShowHidden(g_pact.rows[lon].uid);g_dirty=true;Render();CHECK(g_pflag_n==0 && LineOf(l,0)>=0);
    CHECK(PPPress(500,285));{long lp=27;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYDOWN,lp,dp,sp);CHECK(g_psel_uid==0);}   // Esc
    BeginMouse(500,285);CHECK(g_psel_uid==g_pact.rows[lon].uid);BeginMouse(500,100);CHECK(g_psel_uid==0);                         // a click elsewhere
    CHECK(PPPress(500,285));PPChipClick("Row");CHECK(g_peditor && g_ptab==3 && g_ppage==3);ClosePoints();PPClearSel();

    // ---- alerts: once, when price takes a level of a row that asks for it
    {
     int s0=g_sounds,p0=g_pushes;
     g_pact.rows[lon].alert=true;g_pact.alert_sound=true;g_pact.alert_push=true;
     g_test_now=SV(2026,11,17,13,5)+30;PPMakeBars(g_test_now);PPBuild();
     int i=OccOf(lon,dtue);g_pocc[i].state=0;PPRead(i,g_test_now);PPResetTaken(g_pocc[i],FPPK_WINDOW);
     for(int k=0;k<5;k++)PPScanAlert(i,g_test_now);
     CHECK(g_pocc[i].tk[0]==SV(2026,11,17,13,5) && g_sounds==s0+1 && g_pushes==p0+1);
     PPResetTaken(g_pocc[i],FPPK_WINDOW);for(int k=0;k<5;k++)PPScanAlert(i,g_test_now);CHECK(g_sounds==s0+1);    // another chart: already claimed
     int as=OccOf(asia,dtue);g_pact.rows[asia].alert=true;g_pocc[as].state=0;PPRead(as,g_test_now);PPResetTaken(g_pocc[as],FPPK_WINDOW);
     for(int k=0;k<5;k++)PPScanAlert(as,g_test_now);
     CHECK(g_pocc[as].tk[0]==SV(2026,11,17,5,12) && g_sounds==s0+1);                                               // taken hours ago: no alert
     g_test_now=SV(2026,11,17,13,59)+20;PPMakeBars(g_test_now);for(int k=0;k<5;k++)PPScanAlert(i,g_test_now);
     CHECK(g_pocc[i].scan_to==SV(2026,11,17,13,59) && g_sounds==s0+1);                                              // up to date (the forming candle is read again)
     g_test_now=SV(2026,11,17,14,0)+20;PPMakeBars(g_test_now);PPSetBar(2026,11,17,14,0,1.1,1.1001,1.0960,1.0965);
     CHECK(!PPTail(g_test_now) && g_pocc[i].tk[1]==0);                                                              // the forming candle, not low enough yet
     g_test_now+=20;PPSetBar(2026,11,17,14,0,1.1,1.1001,1.0940,1.0945);
     CHECK(PPTail(g_test_now) && g_pocc[i].tk[1]==SV(2026,11,17,14,0) && g_sounds==s0+2 && g_pushes==p0+2);        // it grows and takes London's low
     CHECK(!PPTail(g_test_now) && g_sounds==s0+2);
     g_pact.rows[lon].alert=false;g_pact.rows[asia].alert=false;
    }

    // ---- the Price points window
    g_test_now=SV(2026,11,17,14,0);PPMakeBars(g_test_now);
    g_pstore="mem.points";g_disk.erase("mem.points");g_pcfg=pc;g_pact=g_pcfg;g_pocc_dirty=true;
    CHECK(SavePoints() && g_disk.count("mem.points")==1);
    OpenPoints();CHECK(g_peditor && g_pedit.count==30 && g_ptab==3);
    g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("N.Tab3"))>=0 && RegFind(UIS("N.Name1"))>=0 && RegFind(UIS("T.Points"))>=0);
    CHECK(HitUI(g_panel_x+U(FPP_PANEL_WIDTH)-5,g_panel_y+10));
    OpenZones();CHECK(!g_zeditor);OpenRisk();CHECK(!g_reditor);ToggleList();CHECK(!g_list);                        // one window at a time
    {g_count=1;MakeFib(g_sets[0],95,"Fib",false,PERIOD_H1);g_selected=0;OpenEditor();CHECK(!g_editor);g_count=0;g_selected=-1;}
    // The table: rows and parts switched, previewed on the chart.
    PointsClick("On1");CHECK(g_pedit.rows[0].enabled && g_pact.rows[0].enabled && g_pocc_dirty);
    PointsClick("P"+IntegerToString(FPPP_BOX)+"_1");CHECK((g_pedit.rows[0].parts&FPPP_BOX)==0);
    PointsClick("P"+IntegerToString(FPPP_H|FPPP_L)+"_19");CHECK((g_pedit.rows[18].parts&(FPPP_H|FPPP_L))==(FPPP_H|FPPP_L));
    PointsClick("P"+IntegerToString(FPPP_O)+"_25");CHECK((g_pedit.rows[24].parts&FPPP_O)==0);                    // not a part of a window
    // Times: HH:MM, checked.
    g_ppage=0;g_ui_dirty=true;BuildUI();g_edit_error=false;
    ObjectSetString(0,UIS("N.Start6"),OBJPROP_TEXT,"25:00");PEndEdit(UIS("N.Start6"));CHECK(g_pedit.rows[5].start==480 && g_edit_error);
    g_ui_dirty=true;BuildUI();
    ObjectSetString(0,UIS("N.Start6"),OBJPROP_TEXT,"7:45");PEndEdit(UIS("N.Start6"));CHECK(g_pedit.rows[5].start==465);
    ObjectSetString(0,UIS("N.End6"),OBJPROP_TEXT,"07:45");PEndEdit(UIS("N.End6"));CHECK(g_pedit.rows[5].end==570);    // can't end where it starts
    g_ppage=2;g_ui_dirty=true;BuildUI();
    ObjectSetString(0,UIS("N.End19"),OBJPROP_TEXT,"10:15");PEndEdit(UIS("N.End19"));CHECK(g_pedit.rows[18].len==45);
    ObjectSetString(0,UIS("N.End19"),OBJPROP_TEXT,"14:00");PEndEdit(UIS("N.End19"));CHECK(g_pedit.rows[18].len==45);  // over 4 hours: refused
    g_ui_dirty=true;BuildUI();
    PointsClick("Tab0");g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("N.Days"))>=0 && RegFind(UIS("N.Week0"))>=0);
    ObjectSetString(0,UIS("N.Days"),OBJPROP_TEXT,"90");PEndEdit(UIS("N.Days"));CHECK(g_pedit.days_back==60);
    g_edit_error=false;ObjectSetString(0,UIS("N.Weeks"),OBJPROP_TEXT,"x");PEndEdit(UIS("N.Weeks"));CHECK(g_pedit.weeks_back==4 && g_edit_error);
    g_ui_dirty=true;BuildUI();
    PointsClick("EndTaken");CHECK(!g_pedit.end_taken && !g_pact.end_taken);PointsClick("EndTaken");
    PointsClick("Taken2");CHECK(g_pedit.taken_show==2);PointsClick("Taken0");
    PointsClick("Week1");CHECK(g_pedit.week_open==1 && g_pocc_dirty);PointsClick("Week0");
    PointsClick("Grp3");CHECK(!g_pedit.group_on[3]);PointsClick("Grp3");
    {int s0=g_sounds;PointsClick("Test");CHECK(g_sounds==s0+1);}
    PointsClick("Tab1");PointsClick("Lbl2");CHECK(g_pedit.label_mode==2);PointsClick("FsUp");CHECK(g_pedit.label_size==11);
    PointsClick("Merge");CHECK(!g_pedit.merge);PointsClick("TfDn5");CHECK(g_pedit.group_tf[5]==18);
    PointsClick("Tab2");g_ui_dirty=true;BuildUI();CHECK(g_slider_on && RegFind(UIS("N.OpThumb"))>=0);
    PointsClick("Tint1");CHECK(g_pedit.tint==1);PointsClick("Range");CHECK(g_pedit.range_fill);
    SliderMouse(g_slider_x0+(g_slider_x1-g_slider_x0)/2,g_slider_y0+5,true,false);SliderMouse(g_slider_x0+(g_slider_x1-g_slider_x0)/2,g_slider_y0+5,false,true);
    CHECK(g_pedit.opacity==50 && g_pact.opacity==50);
    // Dropdowns and colour of a row (London is on page 4).
    PointsClick("Tab3");g_ppage=3;g_ui_dirty=true;BuildUI();
    PointsClick("Style26");CHECK(g_popup==20 && g_popup_items==6);DropdownChoice(2);ClosePopup();CHECK(g_pedit.rows[25].style==1);
    PointsClick("Ends26");CHECK(g_popup==23 && g_popup_items==3);DropdownChoice(2);ClosePopup();CHECK(g_pedit.rows[25].ends==2);
    PointsClick("Label26");CHECK(g_popup==22);DropdownChoice(3);ClosePopup();CHECK(g_pedit.rows[25].label==3);
    PointsClick("Width26");CHECK(g_popup==21);DropdownChoice(2);ClosePopup();CHECK(g_pedit.rows[25].width==3);
    PointsClick("Color26");CHECK(g_popup==3 && g_picker_target==-2025);PickApply(clrGold);
    CHECK(g_pedit.rows[25].ink==clrGold && g_pact.rows[25].ink==clrGold && g_popup==0);
    // A row's options: they stay open while the table behind them is rebuilt.
    g_ui_dirty=true;BuildUI();
    PointsClick("More26");CHECK(g_popup==16 && g_popup_row==25 && RegFind(Obj("Q.Ray"))>=0 && RegFind(Obj("Q.HName"))>=0 && RegFind(Obj("Q.S1"))>=0);
    PPPopupClick(Obj("Q.Ray"));CHECK(g_pedit.rows[25].ray && g_ppopup_reopen==25 && g_ui_dirty);
    ClosePopup();BuildUI();CHECK(g_popup==16 && g_popup_row==25 && g_ppopup_reopen==-1);
    PPPopupClick(Obj("Q.Alert"));ClosePopup();BuildUI();CHECK(g_pedit.rows[25].alert && g_popup==16);
    PPPopupClick(Obj("Q.S1"));ClosePopup();BuildUI();CHECK(g_pedit.rows[25].sample==1);
    PPPopupClick(Obj("Q.S0"));ClosePopup();BuildUI();
    ObjectSetString(0,Obj("Q.HName"),OBJPROP_TEXT," London high ");PPPopupEndEdit(Obj("Q.HName"));CHECK(g_pedit.rows[25].hname=="London high");
    PPPopupClick(Obj("Q.G1"));ClosePopup();BuildUI();CHECK(g_pedit.rows[25].group==1 && g_popup==16);
    PPPopupClick(Obj("Q.K3"));ClosePopup();BuildUI();CHECK(g_pedit.rows[25].kind==FPPK_FVG && g_pedit.rows[25].parts==(FPPP_BOX|FPPP_CE) && RegFind(Obj("Q.Len"))>=0);
    ObjectSetString(0,Obj("Q.Len"),OBJPROP_TEXT,"45");PPPopupEndEdit(Obj("Q.Len"));CHECK(g_pedit.rows[25].len==45);
    ObjectSetString(0,Obj("Q.Len"),OBJPROP_TEXT,"abc");PPPopupEndEdit(Obj("Q.Len"));CHECK(g_pedit.rows[25].len==45);
    PPPopupClick(Obj("Q.Done"));CHECK(g_popup==0);
    {uint u=g_pedit.rows[24].uid;PPSetFlags(u,dtue,4);g_ui_dirty=true;BuildUI();
     PointsClick("More25");CHECK(RegFind(Obj("Q.Show"))>=0);PPPopupClick(Obj("Q.Show"));CHECK(PPHiddenCount(u)==0);ClosePopup();}
    // Sorting: by name (again to reverse), by time of day (evening rows first, periods last).
    PointsClick("SortName");CHECK(g_pedit.rows[0].name=="Asia" && g_psort==1 && !g_psort_desc && g_ui_dirty);
    PointsClick("SortName");CHECK(g_pedit.rows[0].name=="Week" && g_psort_desc && FindRow(g_pedit,"Asia")>=0 && g_pedit.rows[FindRow(g_pedit,"Asia")].start==1140);   // stale table: rows found by identity
    PointsClick("SortTime");CHECK(g_pedit.rows[0].name=="NWOG" && g_pedit.rows[1].name=="NDOG" && g_pedit.rows[2].name=="Asia" && g_pedit.rows[29].name=="Month");
    // Add (in the filtered group), remove, defaults.
    PointsClick("Flt4");CHECK(g_pfilter==3);
    PPSetFlags(31,dtue,4);CHECK(FPPNewUid(g_pedit)==32);PPSetFlags(31,dtue,0);                                     // never an identity with stored levels
    PointsClick("Add");CHECK(g_pedit.count==31 && g_pedit.rows[30].kind==FPPK_FVG && g_pedit.rows[30].group==3 && g_pedit.rows[30].uid==31);
    PointsClick("Flt1");PointsClick("Add");CHECK(g_pedit.count==32 && g_pedit.rows[31].kind==FPPK_WINDOW && g_pedit.rows[31].group==4 && g_pfilter==-1);
    PointsClick("Remove32");
    {FPPointConfig before=g_pedit;PointsClick("Remove31");          // the table still shows row 32: its boxes are skipped
     bool same=g_pedit.count==before.count-1 && g_pedit.days_back==before.days_back && g_pedit.weeks_back==before.weeks_back && g_pedit.months_back==before.months_back
               && g_pedit.label_size==before.label_size && g_pedit.opacity==before.opacity && g_pedit.taken_show==before.taken_show && g_pedit.week_open==before.week_open
               && g_pedit.label_mode==before.label_mode && g_pedit.tint==before.tint && g_pedit.enabled==before.enabled && g_pedit.end_taken==before.end_taken;
     for(int g=0;g<FPP_GROUPS;g++)same=same && g_pedit.group_tf[g]==before.group_tf[g] && g_pedit.group_on[g]==before.group_on[g];
     for(int i=0;i<30;i++)same=same && g_pedit.rows[i].uid==before.rows[i].uid && g_pedit.rows[i].start==before.rows[i].start && g_pedit.rows[i].end==before.rows[i].end;
     CHECK(same);}
    CHECK(g_pedit.count==30);
    PointsClick("Defaults");CHECK(g_pedit.count==30 && g_pedit.rows[25].name=="London" && g_pedit.rows[25].kind==FPPK_WINDOW && !g_pedit.rows[0].enabled);
    // Cancel: nothing kept. OK: saved for every chart of the workspace.
    PointsClick("On1");PointsClick("Cancel");CHECK(!g_peditor && !g_pact.rows[0].enabled && !g_pcfg.rows[0].enabled);
    OpenPoints();PointsClick("On1");PointsClick("OK");CHECK(!g_peditor && g_pcfg.rows[0].enabled);
    {FPPointConfig back;CHECK(FPPReadFile("mem.points",back) && back.rows[0].enabled);}
    // Presets: saved, loaded; two built in (read-only).
    OpenPoints();g_preset_name="My points";PresetBrowser(true);CHECK(g_popup==4 && g_preset_points && !g_preset_zones);
    PresetAction();CHECK(g_disk.count("FibonacciPro\\Presets\\My points.fpt")==1);
    PresetBrowser(false);CHECK(g_preset_count==2 && g_preset_names[0]==FPP_BUILTIN_ICT && g_preset_names[1]==FPP_BUILTIN_OFF);
    ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,FPP_BUILTIN_OFF);PresetAction();
    {bool any=false;for(int i=0;i<g_pedit.count;i++)if(g_pedit.rows[i].enabled)any=true;CHECK(!any && g_pedit.count==30);}
    PresetBrowser(false);ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,"My points");PresetAction();CHECK(g_pedit.rows[0].enabled && g_pedit.rows[1].enabled);
    PresetBrowser(false);ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,FPP_BUILTIN_ICT);PresetDelete();
    CHECK(g_texts[Obj("R.Message")].find("can't be deleted")!=string::npos);
    PresetBrowser(true);ObjectSetString(0,Obj("R.Name"),OBJPROP_TEXT,FPP_BUILTIN_ICT);PresetAction();
    CHECK(g_texts[Obj("R.Message")].find("read-only")!=string::npos);
    ClosePopup();PointsClick("Cancel");
    // ---- the toolbar button and the shortcut
    g_ui_dirty=true;BuildUI();CHECK(RegFind(UIS("T.Points"))>=0 && HitPointsButton(g_toolbar_x+U(FP_TOOLBAR_WIDTH-200),g_toolbar_y+U(5)));
    CHECK(!HitPointsButton(g_toolbar_x+U(FP_TOOLBAR_WIDTH-150),g_toolbar_y+U(5)));                                    // that is Risk
    TogglePointsShown();CHECK(!g_pcfg.enabled && !g_pact.enabled);TogglePointsShown();CHECK(g_pcfg.enabled && g_pact.enabled);
    {int key=0;bool c=false,s=false,al=false;CHECK(ParseHotkey(InpPointsHotkey,key,c,s,al) && key=='L' && c && s && !al);}
    g_points_key='K';CHECK(ShortcutsClash());g_points_key='L';CHECK(!ShortcutsClash());
    Click(UIS("T.Points"));CHECK(g_peditor);Click(UIS("T.Points"));CHECK(!g_peditor);

    // ---- once a second: a live window becomes final and is scanned; at 17:00 the trading day rolls
    {
     g_pcfg=pc;g_pact=g_pcfg;g_pocc_dirty=true;g_test_now=SV(2026,11,17,16,59);PPMakeBars(g_test_now);
     ulong tk=900000;
     for(int k=0;k<30;k++){tk+=1000;PPTick(tk);}
     int nyo=OccOf(nys,dtue);CHECK(nyo>=0 && g_pocc[nyo].live && g_pocc[nyo].state==1 && g_pocc[nyo].hi==1.1051 && g_pp_daykey==(int)dtue);
     PPTick(tk+10);CHECK(g_pp_tick==tk);                                                       // not again within the second
     g_test_now=SV(2026,11,17,17,1);PPMakeBars(g_test_now);
     for(int k=0;k<30;k++){tk+=1000;PPTick(tk);}
     nyo=OccOf(nys,dtue);
     CHECK(g_pp_daykey==(int)(dtue+1) && nyo>=0 && !g_pocc[nyo].live && g_pocc[nyo].state==1 && g_pocc[nyo].formed==SV(2026,11,17,17,0) && g_pocc[nyo].scan_to==0);   // no candles until the 18:00 reopen
     CHECK(OccOf(nys,dtue+1)>=0 && g_pocc[OccOf(nys,dtue+1)].future);                         // Wednesday's session: not yet
     g_points_key_held=true;{long lp=76;double dp=0;string sp="";OnChartEvent(CHARTEVENT_KEYUP,lp,dp,sp);CHECK(!g_points_key_held);}
    }
    // ---- numbered drawing names per timeframe and type
    g_count=0;g_next_uid=100;
    FPSetup s1;MakeFib(s1,1,"",false,PERIOD_H1);s1.kind=FPK_FVG;s1.dir=1;s1.name=FPDefaultName(s1);g_sets[g_count++]=s1;
    CHECK(s1.name=="H1 FVG 1 "+Glyph(0x25B2));
    FPSetup s2=s1;s2.uid=2;s2.dir=2;s2.name=FPDefaultName(s2);CHECK(s2.name=="H1 FVG 2 "+Glyph(0x25BC));g_sets[g_count++]=s2;   // both directions share the count
    FPSetup s3=s1;s3.uid=3;s3.source_tf=PERIOD_M15;s3.name=FPDefaultName(s3);CHECK(s3.name=="M15 FVG 1 "+Glyph(0x25B2));g_sets[g_count++]=s3;   // each timeframe its own
    FPSetup s4=s1;s4.uid=4;s4.name="H1 FVG "+Glyph(0x25B2);g_sets[g_count++]=s4;   // a 1.65 name: no number (counts as 1)
    FPSetup s5=s1;s5.uid=5;s5.name="H1 FVG 7";g_sets[g_count++]=s5;                // numbers in use are kept
    FPSetup s6=s1;s6.uid=6;s6.name="H1 FVG london";g_sets[g_count++]=s6;           // a name of your own
    FPSetup s7=s1;s7.uid=7;CHECK(FPDefaultName(s7)=="H1 FVG 8 "+Glyph(0x25B2));
    CHECK(FPNextNumber(g_sets[4])==3);                                                       // a drawing is not counted against itself
    CHECK(FPNameNumber("H1 FVG 12 "+Glyph(0x25B2),"H1 FVG")==12 && FPNameNumber("H1 FVG","H1 FVG")==1 && FPNameNumber("H1 FVGX","H1 FVG")==0);
    CHECK(FPNameNumber("H1 FVG copy 5","H1 FVG")==0 && FPNameNumber("H1 FVG 1234567","H1 FVG")==0 && FPNameNumber("H1 FVG ","H1 FVG")==0);
    {FPSetup ln;MakeFib(ln,8,"",true,PERIOD_H1);ln.kind=FPK_NONE;CHECK(FPDefaultName(ln)=="H1 Line 1");
     ln.kind=FPK_KH;ln.name="H1 KH 1";g_sets[g_count++]=ln;FPSetup ln2=ln;ln2.uid=9;CHECK(FPDefaultName(ln2)=="H1 KH 2");}
    // Duplicates: a typed name gets the next number; a name of your own gets "copy".
    g_selected=0;g_store="mem.bin";g_editor=false;g_armed=false;g_drag=0;
    DuplicateSelected();CHECK(g_count==8 && g_sets[7].name=="H1 FVG 8 "+Glyph(0x25B2));
    g_selected=5;DuplicateSelected();CHECK(g_count==9 && g_sets[8].name.find("H1 FVG london copy")==0);
    g_count=0;g_selected=-1;g_zact.enabled=true;g_zcfg.enabled=true;
   }

   std::printf(fails?"%d FAILED\n":"all tests passed\n",fails);
   return fails?1:0;
  }
