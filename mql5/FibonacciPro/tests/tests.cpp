// Behavioural tests for Fibonacci_Pro_11.mq5 (1.65), translated to fp5.cpp by translate.py.
#define TEST_OWN_XY
#define TEST_OWN_FILES
#define TEST_OWN_TIME
#define TEST_OWN_RATES
#define TEST_OWN_ALERTS
#define TEST_OWN_OBJGET
#define TEST_OWN_CANVAS
#define TEST_OWN_XYTP
#include "fp5.cpp"
#include <cstdio>
#include <cstring>
#include <map>
#include <algorithm>
#include <cstdlib>
#include <array>
#include "mql5_defaults.h"
// --- stubs the tests observe
string _Symbol="EURUSD";int _Digits=5;double _Point=0.00001;int _Period=PERIOD_H1;
static int g_sets_int=0,g_sets_str=0,g_creates=0,g_deletes=0;static std::map<string,bool> g_objs;static std::map<string,string> g_texts;
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectDelete(long,const string& n){g_deletes++;g_objs.erase(n);return true;}
int ObjectsDeleteAll(long,const string& p,int,int){int k=0;for(auto it=g_objs.begin();it!=g_objs.end();){if(it->first.rfind(p,0)==0){it=g_objs.erase(it);k++;}else ++it;}return k;}
int ObjectFind(long,const string& n){return g_objs.count(n)?0:-1;}
bool ObjectSetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,long){g_sets_int++;return true;}
bool ObjectSetString(long,const string& n,ENUM_OBJECT_PROPERTY_STRING p,const string& v){g_sets_str++;if(p==OBJPROP_TEXT)g_texts[n]=v;return true;}
string ObjectGetString(long,const string& n,ENUM_OBJECT_PROPERTY_STRING,int){auto it=g_texts.find(n);return it==g_texts.end()?"":it->second;}
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
static datetime g_test_now=0;
datetime TimeTradeServer(){return g_test_now;}datetime TimeGMT(){return g_test_now-2*3600;}datetime TimeCurrent(){return g_test_now;}
static std::vector<MqlRates> g_bars;
int CopyRates(const string&,ENUM_TIMEFRAMES,datetime from,datetime to,MQLArr<MqlRates>& r)
  {r.v.clear();for(auto& b:g_bars)if(b.time>=from && b.time<=to)r.v.push_back(b);return (int)r.v.size();}
static std::map<string,double> g_gv;static int g_sounds=0,g_pushes=0;
bool PlaySound(const string&){g_sounds++;return true;}bool SendNotification(const string&){g_pushes++;return true;}
bool GlobalVariableTemp(const string& n){if(g_gv.count(n))return false;g_gv[n]=0;return true;}
bool GlobalVariableSetOnCondition(const string& n,double v,double c){auto it=g_gv.find(n);if(it==g_gv.end() || it->second!=c)return false;it->second=v;return true;}
// In-memory files (1 byte per character).
struct MemFile{string name,data;size_t pos=0;bool write=false;};
static std::map<string,string> g_disk;static std::map<int,MemFile> g_open;static int g_next_handle=1;
int FileOpen(const string& n,int flags,short,uint)
  {MemFile f;f.name=n;f.write=(flags&FILE_WRITE)!=0;if(!f.write){auto it=g_disk.find(n);if(it==g_disk.end())return INVALID_HANDLE;f.data=it->second;}g_open[g_next_handle]=f;return g_next_handle++;}
void FileClose(int h){auto it=g_open.find(h);if(it==g_open.end())return;if(it->second.write)g_disk[it->second.name]=it->second.data;g_open.erase(it);}
void FileFlush(int){}
template<class T> static uint MemWrite(int h,const T& v){g_open[h].data.append((const char*)&v,sizeof(T));return sizeof(T);}
template<class T> static T MemRead(int h){MemFile& f=g_open[h];T v{};if(f.pos+sizeof(T)<=f.data.size())std::memcpy(&v,&f.data[f.pos],sizeof(T));f.pos+=sizeof(T);return v;}
uint FileWriteInteger(int h,int v,int){return MemWrite(h,v);}uint FileWriteLong(int h,long v){return MemWrite(h,v);}uint FileWriteDouble(int h,double v){return MemWrite(h,v);}
uint FileWriteString(int h,const string& s,int len){string t=len<0?s:s.substr(0,len);g_open[h].data+=t;return (uint)t.size();}
int FileReadInteger(int h,int){return MemRead<int>(h);}long FileReadLong(int h){return MemRead<long>(h);}double FileReadDouble(int h){return MemRead<double>(h);}
string FileReadString(int h,int len){MemFile& f=g_open[h];string s=f.data.substr(std::min(f.pos,f.data.size()),len);f.pos+=len;return s;}
bool FileIsEnding(int h){return g_open[h].pos>=g_open[h].data.size();}
ulong FileTell(int h){return g_open[h].pos;}ulong FileSize(int h){return g_open[h].data.size();}
bool FileIsExist(const string& n,int){return g_disk.count(n)>0;}
bool FileCopy(const string& a,int,const string& b,int){if(!g_disk.count(a))return false;g_disk[b]=g_disk[a];return true;}
bool FileMove(const string& a,int,const string& b,int){if(!g_disk.count(a))return false;g_disk[b]=g_disk[a];g_disk.erase(a);return true;}
bool FileDelete(const string& n,int){return g_disk.erase(n)>0;}
long FileFindFirst(const string&,string&,int){return INVALID_HANDLE;}bool FileFindNext(long,string&){return false;}void FileFindClose(long){}
double MathAbs(double v){return std::fabs(v);}double MathRound(double v){return std::round(v);}double MathFloor(double v){return std::floor(v);}
double MathMod(double a,double b){return std::fmod(a,b);}bool MathIsValidNumber(double v){return std::isfinite(v);}
double NormalizeDouble(double v,int d){double m=std::pow(10.0,d);return std::round(v*m)/m;}
string IntegerToString(long v,int,ushort){return std::to_string(v);}
string DoubleToString(double v,int d){char b[64];std::snprintf(b,sizeof b,"%.*f",d,v);return b;}
int StringFind(const string& s,const string& m,int st){size_t r=s.find(m,st);return r==string::npos?-1:(int)r;}
int StringLen(const string& s){return (int)s.size();}
int StringReplace(string& s,const string& f,const string& r){int n=0;size_t p=0;while((p=s.find(f,p))!=string::npos){s.replace(p,f.size(),r);p+=r.size();n++;}return n;}
bool StringToLower(string& s){std::transform(s.begin(),s.end(),s.begin(),::tolower);return true;}
int StringTrimLeft(string& s){size_t p=s.find_first_not_of(' ');s=p==string::npos?"":s.substr(p);return 0;}
int StringTrimRight(string& s){size_t p=s.find_last_not_of(' ');s=p==string::npos?"":s.substr(0,p+1);return 0;}
int StringCompare(const string& a,const string& b,bool cs){string x=a,y=b;if(!cs){StringToLower(x);StringToLower(y);}return x<y?-1:(x>y?1:0);}

static int fails=0;
#define CHECK(c) do{if(!(c)){fails++;std::printf("FAIL line %d: %s\n",__LINE__,#c);}}while(0)
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
    CHECK(u.kind==FPK_NONE && u.levels[0].style==STYLE_SOLID && u.name=="H4 Fib");                 // unmatched: KR style
    // A line drawn on a template's 50% level keeps its price once it becomes a one-level KH.
    FPSetup l;NewSetup(l);l.source_tf=PERIOD_H1;l.hline=true;l.count=1;DefaultLevel(l.levels[0],.5);
    l.pb=106.4;l.pa=107.4;l.left=g_bars[1].time;l.right=l.left+36000;l.ta=l.left;l.tb=l.right;l.ray_right=true;
    AutoType(l);
    CHECK(l.kind==FPK_KH && l.count==1 && LineLevel(l)==0 && std::fabs(FPLevelPrice(l.pa,l.pb,l.levels[0].value)-106.9)<1e-9 && l.name=="H1 KH" && l.ray_right);
    FPSetup ld;NewSetup(ld);ld.source_tf=PERIOD_H1;ld.hline=true;ld.count=1;DefaultLevel(ld.levels[0],0);
    ld.pb=106.9;ld.pa=107.9;ld.left=g_bars[1].time;ld.right=ld.left+36000;ld.ta=ld.left;ld.tb=ld.right;ld.ray_right=false;
    AutoType(ld);CHECK(ld.kind==FPK_KH && !ld.ray_right);                     // a line dragged to length stays that length
    FPSetup mn;NewSetup(mn);mn.source_tf=PERIOD_MN1;mn.kind=FPK_KR;CHECK(FPDefaultName(mn)=="MN KR");
    mn.source_tf=PERIOD_H4;mn.kind=FPK_FVG;mn.dir=1;CHECK(FPDefaultName(mn)=="H4 FVG "+Glyph(0x25B2));
    mn.dir=2;CHECK(FPDefaultName(mn)=="H4 FVG "+Glyph(0x25BC));mn.dir=0;CHECK(FPDefaultName(mn)=="H4 FVG");
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
    CHECK(g_count==1 && g_sets[0].name=="H1 Fib" && g_sets[0].count==12 && !g_sets[0].fill && g_sets[0].levels[0].style==STYLE_SOLID);
    Arm();BeginMouse(300,200);EndMouse(300,200);                              // a single click: a line
    CHECK(g_count==2 && g_sets[1].hline && g_sets[1].name=="H1 Line" && g_sets[1].count==1 && g_sets[1].levels[0].ink==InpColorH1);
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

   std::printf(fails?"%d FAILED\n":"all tests passed\n",fails);
   return fails?1:0;
  }
