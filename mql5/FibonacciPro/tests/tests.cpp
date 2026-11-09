// Behavioural tests for Fibonacci_Pro_6.mq5 (translated to fp5.cpp by translate.py).
#include "fp5.cpp"
#include <cstdio>
#include <map>
#include <algorithm>
#include <cstdlib>
#include "mql5_defaults.h"
// --- stub implementations used by the code under test
string _Symbol="EURUSD";int _Digits=5;double _Point=0.00001;int _Period=PERIOD_H1;
static int g_sets_int=0,g_sets_str=0,g_creates=0,g_deletes=0,g_moves=0;static std::map<string,bool> g_objs;
static int Commands(){return g_sets_int+g_sets_str+g_creates+g_deletes+g_moves;}
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectMove(long,const string&,int,datetime,double){g_moves++;return true;}
bool ObjectDelete(long,const string& n){g_deletes++;g_objs.erase(n);return true;}
int ObjectsDeleteAll(long,const string& p,int,int){int k=0;for(auto it=g_objs.begin();it!=g_objs.end();){if(it->first.rfind(p,0)==0){it=g_objs.erase(it);k++;}else ++it;}g_deletes+=k;return k;}
int ObjectFind(long,const string& n){return g_objs.count(n)?0:-1;}
bool ObjectSetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,long){g_sets_int++;return true;}
bool ObjectSetString(long,const string&,ENUM_OBJECT_PROPERTY_STRING,const string&){g_sets_str++;return true;}
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
   s.ta=1000;s.tb=9000;s.pa=1.2;s.pb=1.1;s.left=1000;s.right=9000;s.ray_left=false;s.ray_right=false;
   s.diagonal=true;s.labels=true;s.label_v=0;s.label_h=0;s.label_float=true;s.anchors_locked=false;s.base_color=clrRed;
   s.fill=false;s.count=3;double r[]={0,.5,1};
   for(int i=0;i<3;i++){s.levels[i].enabled=true;s.levels[i].value=r[i];s.levels[i].description=FP_DEFAULT_TEXT;s.levels[i].style=0;s.levels[i].width=1;s.levels[i].ink=clrBlue;}
  }

int main()
  {
   g_prefix="FP5.Main.abc123.";g_scale=1.0;g_tf=11;g_width=1000;g_height=600;

   // ---- label placement rules
   CHECK(FPLabelMode(0,false,false,true)==1);   // not rayed: anchored at the origin
   CHECK(FPLabelMode(0,true,false,true)==2);    // left label, rayed left, floating: pinned to edge
   CHECK(FPLabelMode(0,true,false,false)==1);   // fixed: stays at the origin
   CHECK(FPLabelMode(1,false,true,true)==2);    // right label, rayed right, floating: pinned
   CHECK(FPLabelMode(1,true,false,true)==1);    // ray on the other side does not pin
   CHECK(FPLabelAnchor(0,0)==ANCHOR_LEFT_LOWER && FPLabelAnchor(0,1)==ANCHOR_RIGHT_LOWER);
   CHECK(FPLabelAnchor(1,0)==ANCHOR_LEFT_UPPER && FPLabelAnchor(1,1)==ANCHOR_RIGHT_UPPER);

   // ---- visibility masks (new drawings always visible where drawn; higher TFs allowed)
   int m5=4,h1=11,h4=14;
   long custom=((long)1<<m5)|((long)1<<h1);
   CHECK((FPAdaptMask(custom,h1,h4,0)&((long)1<<h4))!=0);
   CHECK(FPAdaptMask(FPAllowedMask(h1),h1,h4,1)==FPAllowedMask(h4));
   CHECK(FPAdaptMask(FP_ALL_TF_MASK,h1,m5,0)==FP_ALL_TF_MASK);
   FPSetup v;v.visible_mask=(long)1<<16;CHECK(!Visible(v));g_tf=16;CHECK(Visible(v));g_tf=h1;

   // ---- native objects: created once, then only changed properties are sent
   g_count=2;MakeFib(g_sets[0],1,"Alpha",false,PERIOD_H1);MakeFib(g_sets[1],2,"Beta",true,PERIOD_H4);
   g_sets[1].levels[1].enabled=false;g_sets[1].levels[2].enabled=false;g_sets[1].diagonal=false;
   g_selected=-1;SyncAll();
   CHECK(g_objs.count(NatName(1,"L0")) && g_objs.count(NatName(1,"T2")) && g_objs.count(NatName(1,"D")));
   CHECK(g_objs.count(NatName(2,"L0")) && !g_objs.count(NatName(2,"L1")) && !g_objs.count(NatName(2,"D")));
   CHECK(g_relayer);g_relayer=false;
   int before=Commands();SyncAll();
   CHECK(Commands()==before && !g_relayer);                       // nothing changed: zero commands
   g_sets[0].pa=1.25;before=Commands();int moves=g_moves;SyncAll();
   CHECK(g_moves>moves && !g_relayer);                            // anchors moved: ObjectMove, no new objects
   CHECK(g_creates==g_creates);
   g_sets[0].levels[1].enabled=false;SyncAll();
   CHECK(!g_objs.count(NatName(1,"L1")) && !g_objs.count(NatName(1,"T1")));
   g_sets[0].visible_mask=0;SyncAll();                             // hidden on this timeframe
   CHECK(!g_objs.count(NatName(1,"L0")) && g_nat[0].uid==0);
   g_sets[0].visible_mask=FP_ALL_TF_MASK;g_sets[0].levels[1].enabled=true;SyncAll();
   CHECK(g_objs.count(NatName(1,"L1")) && g_relayer);g_relayer=false;
   // Selection grips: hidden, not deleted, when the selection goes away.
   g_selected=0;SyncAll();CHECK(g_grip[0].on && g_grip[0].shown && g_grip[4].on);
   g_relayer=false;g_selected=-1;SyncAll();g_selected=0;SyncAll();
   CHECK(g_grip[0].shown && !g_relayer);                           // re-shown without re-creation
   g_selected=-1;SyncAll();
   // Deleting slot 0 shifts slot 1's cache down; the vacated slot is clean.
   g_sets[0]=g_sets[1];g_count=1;NatRemoveSlot(0);
   CHECK(g_nat[0].uid==2 && g_nat[0].lv[0].line && g_nat[1].uid==0 && !g_nat[1].lv[0].line);
   CHECK(!g_objs.count(NatName(1,"L0")) && g_objs.count(NatName(2,"L0")));
   before=Commands();g_relayer=false;SyncAll();CHECK(Commands()==before && !g_relayer);
   // Objects deleted by another program are detected and rebuilt.
   g_objs.erase(NatName(2,"L0"));CHECK(NatObjectsMissing());ResetAllNat();SyncAll();
   CHECK(g_objs.count(NatName(2,"L0")) && !NatObjectsMissing());

   // ---- drawings list: filter, search and sort
   g_count=4;MakeFib(g_sets[0],10,"zeta fib",false,PERIOD_H1);MakeFib(g_sets[1],11,"Alpha line",true,PERIOD_M5);
   MakeFib(g_sets[2],12,"beta",false,PERIOD_D1);MakeFib(g_sets[3],13,"Gamma line",true,PERIOD_H1);
   g_sets[2].visible_mask=0;g_sets[2].description="weekly swing";
   g_list_filter=0;g_list_sort=0;g_list_desc=true;g_list_search="";g_list_key="";ListRebuild();
   CHECK(g_list_n==4 && g_list_idx[0]==3 && g_list_idx[3]==0);    // newest first
   g_list_sort=1;g_list_desc=false;ListRebuild();
   CHECK(g_list_idx[0]==1 && g_list_idx[1]==2 && g_list_idx[2]==3 && g_list_idx[3]==0); // name, case-insensitive
   g_list_filter=3;ListRebuild();CHECK(g_list_n==2);              // lines only
   g_list_filter=1;ListRebuild();CHECK(g_list_n==3);              // visible on this TF
   g_list_filter=0;g_list_search="  SWING ";ListRebuild();CHECK(g_list_n==1 && g_list_idx[0]==2); // description search
   g_list_search="";g_list_sort=3;g_list_desc=false;ListRebuild();
   CHECK(g_list_idx[0]==1 && g_list_idx[3]==2);                   // by timeframe M5..D1
   int key_n=g_list_n;g_list_n=-1;ListRebuild();CHECK(g_list_n==-1); // unchanged inputs: no rebuild
   g_save_gen++;ListRebuild();CHECK(g_list_n==key_n);              // a save invalidates it
   // 1000 drawings sort quickly and correctly.
   g_count=1000;for(int i=0;i<1000;i++)MakeFib(g_sets[i],1000-i,"n"+std::to_string((i*7919)%1000),i%3==0,PERIOD_H1);
   g_list_sort=1;g_list_desc=false;g_list_key="";ListRebuild();
   bool sorted=g_list_n==1000;
   for(int i=1;i<g_list_n && sorted;i++)sorted=StringCompare(g_sets[g_list_idx[i-1]].name,g_sets[g_list_idx[i]].name,false)<=0;
   CHECK(sorted);

   // ---- horizontal line math (unchanged from 1.60)
   g_view_min=1.0;g_view_max=1.1;g_height=800;
   FPSetup line;MakeFib(line,7,"x",false,PERIOD_H1);double ratios[]={0,.236,.382,.5,.618,.786,1};
   for(int i=0;i<7;i++){line.levels[i].enabled=true;line.levels[i].value=ratios[i];}line.count=7;
   line.pa=1.05432;line.pb=1.05432;line.ray_left=true;line.fill=true;line.visible_mask=0;
   CHECK(MakeLine(line,false));
   int on=0,k=-1;for(int i=0;i<line.count;i++)if(line.levels[i].enabled){on++;k=i;}
   CHECK(on==1 && line.levels[k].value==0.0 && std::fabs(FPLevelPrice(line.pa,line.pb,0.0)-1.05432)<1e-9);
   CHECK(line.hline && !line.diagonal && !line.fill && (line.visible_mask&((long)1<<h1))!=0);

   std::printf(fails?"%d FAILED\n":"all tests passed\n",fails);
   return fails?1:0;
  }
