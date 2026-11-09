// Behavioural tests for Fibonacci_Pro_7.mq5 (1.61), translated to fp5.cpp by translate.py.
#define TEST_OWN_XY
#include "fp5.cpp"
#include <cstdio>
#include <map>
#include <algorithm>
#include <cstdlib>
#include "mql5_defaults.h"
// --- stubs the tests observe
string _Symbol="EURUSD";int _Digits=5;double _Point=0.00001;int _Period=PERIOD_H1;
static int g_sets_int=0,g_sets_str=0,g_creates=0,g_deletes=0;static std::map<string,bool> g_objs;
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectDelete(long,const string& n){g_deletes++;g_objs.erase(n);return true;}
int ObjectsDeleteAll(long,const string& p,int,int){int k=0;for(auto it=g_objs.begin();it!=g_objs.end();){if(it->first.rfind(p,0)==0){it=g_objs.erase(it);k++;}else ++it;}return k;}
int ObjectFind(long,const string& n){return g_objs.count(n)?0:-1;}
bool ObjectSetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,long){g_sets_int++;return true;}
bool ObjectSetString(long,const string&,ENUM_OBJECT_PROPERTY_STRING,const string&){g_sets_str++;return true;}
// Linear projection: 1 px per minute from t=0, 1000 px per price unit from 2.0 down.
bool ChartTimePriceToXY(long,int,datetime t,double p,int& x,int& y){x=(int)(t/60);y=(int)std::lround((2.0-p)*1000);return true;}
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

static void MakeFib(FPSetup &s,const int uid,const string name,const bool hline,const ENUM_TIMEFRAMES tf)
  {
   s.uid=uid;s.name=name;s.description="";s.hline=hline;s.source_tf=tf;s.visible_mask=FP_ALL_TF_MASK;s.visibility_mode=0;
   s.ta=60000;s.tb=120000;s.pa=1.2;s.pb=1.1;s.left=60000;s.right=120000;s.ray_left=false;s.ray_right=false;
   s.diagonal=true;s.labels=true;s.label_v=0;s.label_h=0;s.label_float=true;s.anchors_locked=false;s.base_color=clrRed;
   s.fill=false;s.opacity=12;s.count=3;double r[]={0,.5,1};
   for(int i=0;i<3;i++){s.levels[i].enabled=true;s.levels[i].value=r[i];s.levels[i].description=FP_DEFAULT_TEXT;s.levels[i].style=0;s.levels[i].width=1;s.levels[i].ink=clrBlue;}
  }

int main()
  {
   g_prefix="FP5.Main.abc123.";g_scale=1.0;g_tf=11;g_width=1000;g_height=600;

   // ---- requested defaults
   CHECK(InpMaximumSetups==1000 && FP_MAX_SETUPS==1000 && MaxSetups()==1000);
   CHECK(InpFrameMilliseconds==8);

   // ---- label placement (1.60 behaviour)
   CHECK(FPLabelX(-200,300,-200,300,50,1000,0,false,false,false,3)==-197);
   CHECK(FPLabelX(-200,300,-200,300,50,1000,0,false,false,true,3)==3);
   CHECK(FPLabelX(100,600,100,999,50,1000,1,false,true,true,3)==1000-1-3-50);

   // ---- visibility masks
   int m5=4,h1=11,h4=14;
   long custom=((long)1<<m5)|((long)1<<h1);
   CHECK((FPAdaptMask(custom,h1,h4,0)&((long)1<<h4))!=0);
   CHECK(FPAdaptMask(FP_ALL_TF_MASK,h1,m5,0)==FP_ALL_TF_MASK);
   FPSetup v;v.visible_mask=(long)1<<16;CHECK(!Visible(v));g_tf=16;CHECK(Visible(v));g_tf=h1;

   // ---- registry: change-only updates and sweep
   g_gen=1;UIBase(UIS("E.A"),OBJ_BUTTON,10,10,50,20,"A");UIBase(UIS("T.New"),OBJ_BUTTON,10,70,50,20,"New");
   int before=g_sets_int+g_sets_str;g_gen=2;UIBase(UIS("T.New"),OBJ_BUTTON,10,70,50,20,"New");
   CHECK(g_sets_int+g_sets_str==before);RegSweep(UIS(""));
   CHECK(RegFind(UIS("E.A"))<0 && RegFind(UIS("T.New"))>=0);RegDeletePrefix(UIS(""));CHECK(g_reg_count==0);

   // ---- culling by visible time window (1 px per minute in this projection)
   FPSetup c;MakeFib(c,5,"c",false,PERIOD_H1);           // spans minutes 1000..2000
   g_cull_ok=true;g_vt0=(datetime)(5000*60);g_vt1=(datetime)(9000*60);
   ComputeGeo(c,0);CHECK(!g_geo[0].valid);                // entirely left of the window
   c.ray_right=true;ComputeGeo(c,0);CHECK(g_geo[0].valid); // a right ray reaches the window
   c.ray_right=false;g_vt0=(datetime)(0);ComputeGeo(c,0);CHECK(g_geo[0].valid && g_geo[0].count==3);
   g_vt0=0;g_vt1=(datetime)(500*60);ComputeGeo(c,0);CHECK(!g_geo[0].valid); // right of the window
   c.ray_left=true;ComputeGeo(c,0);CHECK(g_geo[0].valid);
   g_cull_ok=false;c.ray_left=false;ComputeGeo(c,0);CHECK(g_geo[0].valid); // no window known: never culled

   // ---- drawings list: filter, search, sort
   g_count=4;MakeFib(g_sets[0],10,"zeta fib",false,PERIOD_H1);MakeFib(g_sets[1],11,"Alpha line",true,PERIOD_M5);
   MakeFib(g_sets[2],12,"beta",false,PERIOD_D1);MakeFib(g_sets[3],13,"Gamma line",true,PERIOD_H1);
   g_sets[2].visible_mask=0;g_sets[2].description="weekly swing";
   g_list_filter=0;g_list_sort=0;g_list_desc=true;g_list_search="";g_list_key="";ListRebuild();
   CHECK(g_list_n==4 && g_list_idx[0]==3 && g_list_idx[3]==0);
   g_list_sort=1;g_list_desc=false;ListRebuild();
   CHECK(g_list_idx[0]==1 && g_list_idx[1]==2 && g_list_idx[2]==3 && g_list_idx[3]==0);
   g_list_filter=3;ListRebuild();CHECK(g_list_n==2);
   g_list_filter=1;ListRebuild();CHECK(g_list_n==3);
   g_list_filter=0;g_list_search="  SWING ";ListRebuild();CHECK(g_list_n==1 && g_list_idx[0]==2);
   g_list_search="";g_list_sort=3;ListRebuild();CHECK(g_list_idx[0]==1 && g_list_idx[3]==2);
   int key_n=g_list_n;g_list_n=-1;ListRebuild();CHECK(g_list_n==-1);
   g_save_gen++;ListRebuild();CHECK(g_list_n==key_n);
   // List panel builds with rows, swatches and action buttons.
   g_list=true;g_list_rows=12;g_list_key="";g_selected=1;BuildUI();
   CHECK(RegFind(UIS("L.Row0"))>=0 && RegFind(UIS("L.Here3"))>=0 && RegFind(UIS("L.Del3"))>=0 && RegFind(UIS("L.Row4"))<0);
   CHECK(RegFind(UIS("T.List"))>=0 && RegFind(UIS("L.Empty"))<0);
   g_list_search="nothing-matches";ListClick("L.Find");g_list_search="nothing-matches";BuildUI();
   CHECK(RegFind(UIS("L.Empty"))>=0 && RegFind(UIS("L.Row0"))<0);
   g_list=false;g_list_search="";BuildUI();CHECK(RegFind(UIS("L.Background"))<0);
   // Deleting with a failed save restores the drawings and the selection.
   g_selected=3;RemoveAt(1);CHECK(g_count==4 && g_sets[1].uid==11 && g_selected==3);
   // 1000 drawings sort correctly.
   g_count=1000;for(int i=0;i<1000;i++)MakeFib(g_sets[i],1000-i,"n"+std::to_string((i*7919)%1000),i%3==0,PERIOD_H1);
   g_list_sort=1;g_list_desc=false;g_list_key="";ListRebuild();
   bool sorted=g_list_n==1000;
   for(int i=1;i<g_list_n && sorted;i++)sorted=StringCompare(g_sets[g_list_idx[i-1]].name,g_sets[g_list_idx[i]].name,false)<=0;
   CHECK(sorted);

   // ---- Fibo levels tab: one palette for every level
   g_count=1;MakeFib(g_sets[0],1,"f",false,PERIOD_H1);g_selected=0;g_sets[0].levels[2].ink=clrGreen;
   OpenEditor();g_tab=2;BuildUI();
   int all=RegFind(UIS("E.AllColor"));CHECK(all>=0 && g_reg[all].bg==(int)clrWhite);   // mixed colours
   Palette(-5);CHECK(g_popup==3 && g_picker_target==-5 && g_pick_color==clrBlue);
   PickApply(clrOrange);
   bool same=true;for(int i=0;i<g_edit.count;i++)same=same && g_edit.levels[i].ink==clrOrange;
   CHECK(same && g_sets[0].levels[0].ink==clrBlue);               // editor copy only until Apply
   BuildUI();all=RegFind(UIS("E.AllColor"));CHECK(all>=0 && g_reg[all].bg==(int)clrOrange);
   g_edit.count=0;Palette(-5);CHECK(g_popup==0);                   // nothing to recolour
   CloseEditor();

   // ---- candle tooltip: symbol and timeframe under the date
   color accent=clrNONE;MQLArr<string> tip;CandleTip(0,tip,accent);
   CHECK(ArraySize(tip)==7 && tip[1]=="EURUSD  H1" && StringFind(tip[0],"EURUSD")<0 && StringFind(tip[2],"Open")==0);

   // ---- horizontal line math (1.60 behaviour)
   g_view_min=1.0;g_view_max=1.1;g_height=800;
   FPSetup line;MakeFib(line,7,"x",false,PERIOD_H1);line.pa=1.05432;line.pb=1.05432;line.visible_mask=0;
   CHECK(MakeLine(line,false) && std::fabs(FPLevelPrice(line.pa,line.pb,0.0)-1.05432)<1e-9 && line.hline);

   std::printf(fails?"%d FAILED\n":"all tests passed\n",fails);
   return fails?1:0;
  }
