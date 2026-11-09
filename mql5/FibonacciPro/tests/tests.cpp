#include "fp5.cpp"
#include <cstdio>
#include <map>
// --- stub implementations used by the code under test
string _Symbol="EURUSD";int _Digits=5;double _Point=0.00001;int _Period=PERIOD_H1;
static int g_sets_int=0,g_sets_str=0,g_creates=0,g_deletes=0;static std::map<string,bool> g_objs;
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectDelete(long,const string& n){g_deletes++;g_objs.erase(n);return true;}
int ObjectsDeleteAll(long,const string& p,int,int){int k=0;for(auto it=g_objs.begin();it!=g_objs.end();){if(it->first.rfind(p,0)==0){it=g_objs.erase(it);k++;}else ++it;}return k;}
bool ObjectSetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,long){g_sets_int++;return true;}
bool ObjectSetString(long,const string&,ENUM_OBJECT_PROPERTY_STRING,const string&){g_sets_str++;return true;}
double MathAbs(double v){return std::fabs(v);}double MathRound(double v){return std::round(v);}double MathFloor(double v){return std::floor(v);}
double MathMod(double a,double b){return std::fmod(a,b);}bool MathIsValidNumber(double v){return std::isfinite(v);}
double NormalizeDouble(double v,int d){double m=std::pow(10.0,d);return std::round(v*m)/m;}
string IntegerToString(long v,int,ushort){return std::to_string(v);}
int StringFind(const string& s,const string& m,int st){size_t r=s.find(m,st);return r==string::npos?-1:(int)r;}
int StringLen(const string& s){return (int)s.size();}

static int fails=0;
#define CHECK(c) do{if(!(c)){fails++;std::printf("FAIL line %d: %s\n",__LINE__,#c);}}while(0)

int main()
  {
   // ---- label placement (width 1000, text 50 wide, pad 3)
   // Fixed, left: at the origin even when off-screen.
   CHECK(FPLabelX(-200,300,-200,300,50,1000,0,false,false,false,3)==-197);
   // Float, left, not rayed: clamped into the visible part of the level.
   CHECK(FPLabelX(-200,300,-200,300,50,1000,0,false,false,true,3)==3);
   // Float, left, rayed left: chart left edge (the behaviour of earlier versions).
   CHECK(FPLabelX(400,600,0,600,50,1000,0,true,false,true,3)==3);
   // Fixed, left, rayed left: stays at the Fib origin.
   CHECK(FPLabelX(400,600,0,600,50,1000,0,true,false,false,3)==403);
   // Right side, fixed: ends 3 px before the Fib end even when rayed right.
   CHECK(FPLabelX(100,600,100,999,50,1000,1,false,true,false,3)==547);
   // Right side, float, rayed right: at the chart's right edge.
   CHECK(FPLabelX(100,600,100,999,50,1000,1,false,true,true,3)==1000-1-3-50);
   // Right side, float, end off-screen to the right without ray: kept inside the window.
   CHECK(FPLabelX(100,1500,100,1500,50,1000,1,false,false,true,3)==1000-1-3-50);

   // ---- visibility masks
   int m5=4,h1=11,h4=14;
   long custom=((long)1<<m5)|((long)1<<h1); // custom set drawn on H1
   CHECK((FPAdaptMask(custom,h1,h4,0)&((long)1<<h4))!=0);           // new H4 drawing is visible on H4
   CHECK((FPAdaptMask(custom,h1,h4,0)&((long)1<<m5))!=0);           // custom choices kept
   CHECK(FPAdaptMask(FPAllowedMask(h1),h1,h4,1)==FPAllowedMask(h4)); // "drawing TF & lower" adapts
   CHECK(FPAdaptMask(0,h1,h4,2)==((long)1<<h4));                    // "drawing TF only" adapts
   CHECK(FPAdaptMask(FP_ALL_TF_MASK,h1,m5,0)==FP_ALL_TF_MASK);      // "all timeframes" stays all
   FPSetup s;s.visible_mask=(long)1<<16;g_tf=h1;                     // H8 only
   CHECK(!Visible(s));s.visible_mask|=(long)1<<h1;CHECK(Visible(s));
   s.visible_mask=(long)1<<16;g_tf=16;CHECK(Visible(s));             // higher-TF toggle honoured

   // ---- registry: change-only updates and sweep
   g_prefix="FP5.Main.abc123.";g_scale=1.0;g_gen=1;
   UIBase(UIS("E.A"),OBJ_BUTTON,10,10,50,20,"A");UIBase(UIS("E.B"),OBJ_EDIT,10,40,50,20,"B");
   UIBase(UIS("T.New"),OBJ_BUTTON,10,70,50,20,"New");
   CHECK(g_reg_count==3 && g_creates==3);
   int before=g_sets_int+g_sets_str;
   g_gen=2;UIBase(UIS("E.A"),OBJ_BUTTON,10,10,50,20,"A");
   CHECK(g_sets_int+g_sets_str==before);                              // unchanged: no commands
   UIBase(UIS("E.B"),OBJ_EDIT,10,40,50,20,"B");
   CHECK(g_sets_int+g_sets_str==before+1);                            // edit text always rewritten
   UIBase(UIS("T.New"),OBJ_BUTTON,12,70,50,20,"New");
   CHECK(g_sets_int+g_sets_str==before+2);                            // only XDISTANCE sent
   g_gen=3;UIBase(UIS("T.New"),OBJ_BUTTON,12,70,50,20,"Draw now...");RegSweep(UIS(""));
   CHECK(g_reg_count==1 && RegFind(UIS("T.New"))>=0 && RegFind(UIS("E.A"))<0 && RegFind(UIS("E.B"))<0);
   CHECK(g_objs.count(UIS("E.A"))==0 && g_objs.count(UIS("T.New"))==1);
   RegDeletePrefix(UIS(""));CHECK(g_reg_count==0 && g_objs.empty());
   CHECK(RegType("missing")==-1);

   // ---- horizontal line math: the visible level sits exactly on the clicked price
   g_view_min=1.0;g_view_max=1.1;g_height=800;
   FPSetup line;line.uid=7;line.count=0;double ratios[]={0,.236,.382,.5,.618,.786,1};
   for(int i=0;i<7;i++){line.levels[i].enabled=true;line.levels[i].value=ratios[i];}line.count=7;
   line.ta=1000;line.tb=5000;line.left=1000;line.right=5000;line.pa=1.05432;line.pb=1.05432;
   line.ray_left=true;line.diagonal=true;line.fill=true;line.visible_mask=0;g_tf=h1;
   CHECK(MakeLine(line,false));
   int on=0,k=-1;for(int i=0;i<line.count;i++)if(line.levels[i].enabled){on++;k=i;}
   CHECK(on==1 && line.levels[k].value==0.0);
   CHECK(std::fabs(FPLevelPrice(line.pa,line.pb,line.levels[k].value)-1.05432)<1e-9);
   CHECK(line.pa!=line.pb && line.hline && !line.diagonal && !line.fill && !line.ray_left && !line.ray_right);
   CHECK(LineLevel(line)==k && (line.visible_mask&((long)1<<h1))!=0 && line.left==1000 && line.right==5000);
   // Only a 100% level: the line is placed on pa.
   FPSetup only;only.uid=8;only.count=1;only.levels[0].enabled=true;only.levels[0].value=1.0;
   only.ta=1;only.tb=2;only.left=1;only.right=2;only.pa=2.5;only.pb=2.5;only.visible_mask=0;
   CHECK(MakeLine(only,false) && std::fabs(FPLevelPrice(only.pa,only.pb,1.0)-2.5)<1e-9 && only.pa>only.pb);
   // A dragged line moves both anchors by the same amount: it cannot tilt.
   double gap=line.pa-line.pb;line.pa=NormalizeDouble(line.pa+0.00123,5);line.pb=NormalizeDouble(line.pb+0.00123,5);
   CHECK(std::fabs((line.pa-line.pb)-gap)<1e-9);

   std::printf(fails?"%d FAILED\n":"all tests passed\n",fails);
   return fails?1:0;
  }
