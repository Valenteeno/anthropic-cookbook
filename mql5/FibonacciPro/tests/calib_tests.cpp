// Behavioural tests for Fibonacci_Pro_Calibrate.mq5 (1.66), translated to calib.cpp by translate.py.
#define TEST_OWN_FILES
#define TEST_OWN_TIME
#define TEST_OWN_ALERTS
#define TEST_OWN_OBJGET
#define TEST_OWN_MARKET
#include "calib.cpp"
#include "mql5_defaults.h"
#include "test_common.h"
string _Symbol="US100";int _Digits=2;double _Point=0.01;int _Period=PERIOD_H1;
// The terminal's own calculation: price change x contract size x lots in the profit currency,
// converted to the account currency. It ignores the broker's tick value, as MT5 does.
static bool g_calc_fail=false;static std::map<string,double> g_calc_skew;   // a calculation off by this factor
bool OrderCalcProfit(ENUM_ORDER_TYPE type,const string& sym,double lots,double open,double close,double& profit)
  {
   auto it=g_syms.find(sym);
   if(it==g_syms.end() || g_calc_fail)return false;
   string k="",s="";bool inv=false;
   double conv=FPCConv(it->second.profit,g_acc_ccy,k,s,inv);
   if(!(conv>0))return false;
   profit=(type==ORDER_TYPE_BUY?close-open:open-close)*it->second.contract*lots*conv*(g_calc_skew.count(sym)?g_calc_skew[sym]:1.0);
   return true;
  }
static std::vector<string> g_boxes;
int MessageBox(const string& text,const string&,int){g_boxes.push_back(text);return 1;}

int main()
  {
   g_server="Test-Server";g_acc_ccy="USD";g_test_now=1767225600;
   AddSym("EURUSD","EUR","USD",SYMBOL_CALC_MODE_FOREX,1.1,1.1001,5,0.00001,1.0,100000,true);
   AddSym("US100","USD","USD",SYMBOL_CALC_MODE_CFDINDEX,18000,18001,2,0.01,0.1,1,true);   // the broker's tick value is 10x too high
   AddSym("DE40","EUR","EUR",SYMBOL_CALC_MODE_CFDINDEX,19000,19002,1,0.1,0.11,1,true);
   AddSym("XAUUSD","XAU","USD",SYMBOL_CALC_MODE_CFD,2000,2000.2,2,0.01,1.0,100,true);
   AddSym("DEAD","USD","USD",SYMBOL_CALC_MODE_CFD,0,0,2,0.01,0.01,1,true);                 // no quotes
   string file="FibonacciPro\\Test-Server.calib";
   CHECK(FPCFile()==file);
   // A symbol calibrated earlier and no longer in Market Watch is kept.
   {
    MQLArr<FPCalib> old;ArrayResize(old,1);
    old[0].symbol="OLD";old[0].profit_ccy="USD";old[0].account_ccy="USD";old[0].value_profit=5;old[0].value_account=5;
    old[0].contract=5;old[0].tick_size=0.1;old[0].tick_value=0.5;old[0].time=1;
    CHECK(FPCSave(file,old,1));
   }
   OnStart();
   MQLArr<FPCalib> list;int n=FPCLoad(file,list);
   CHECK(n==5 && FPCFind(list,n,"OLD")==0 && FPCFind(list,n,"DEAD")<0);
   int u=FPCFind(list,n,"US100"),d=FPCFind(list,n,"DE40"),e=FPCFind(list,n,"EURUSD"),x=FPCFind(list,n,"XAUUSD");
   CHECK(u>=0 && d>=0 && e>=0 && x>=0);
   if(u>=0 && d>=0 && e>=0 && x>=0)
     {
      CHECK(list[u].value_account==1 && list[u].value_profit==1 && list[u].tick_value==0.1 && list[u].contract==1 && list[u].time==g_test_now);
      CHECK(std::fabs(list[d].value_account-1.1)<1e-9 && std::fabs(list[d].value_profit-1)<1e-9 && list[d].profit_ccy=="EUR" && list[d].account_ccy=="USD");
      CHECK(std::fabs(list[e].value_account-100000)<1e-4 && std::fabs(list[x].value_account-100)<1e-9);
     }
   CHECK(g_boxes.size()==1);
   if(g_boxes.size()==1)
     {
      const string& t=g_boxes[0];
      CHECK(t.find("Calibrated 4 symbol(s) for server Test-Server.")==0 && t.find("1 skipped")!=string::npos);
      CHECK(t.find("off for: US100.")!=string::npos && t.find("DE40")==string::npos && t.find("XAUUSD")==string::npos);   // only the broken tick value
     }
   CHECK(g_disk.count(file+".csv")==1 && g_disk[file+".csv"].find("\nUS100;USD;1;1;USD;1;0.01;0.1;1767225600\r\n")!=string::npos);
   // A broker changing the contract size: only this chart's symbol, measured again.
   g_boxes.clear();InpAllSymbols=false;g_syms["US100"].contract=10;g_test_now+=60;
   g_disk.erase(file+".bak");
   OnStart();n=FPCLoad(file,list);u=FPCFind(list,n,"US100");
   CHECK(g_disk.count(file+".bak")==1);                                                   // the previous file is kept
   CHECK(n==5 && u>=0 && list[u].value_account==10 && list[u].time==g_test_now && g_boxes.size()==1 && g_boxes[0].find("Calibrated 1 symbol(s)")==0);
   // The tick value now agrees (contract 10 x 0.01 tick = 0.1): nothing is flagged.
   CHECK(g_boxes.size()==1 && g_boxes[0].find("agree with the terminal's calculation")!=string::npos);
   // Not logged in: a message, and the file is left alone.
   g_acc_ccy="";g_boxes.clear();string before=g_disk[file];
   OnStart();CHECK(g_boxes.size()==1 && g_boxes[0].find("Log in")==0 && g_disk[file]==before);
   // A symbol the terminal can't calculate is reported and skipped; the file is kept.
   g_acc_ccy="USD";g_calc_fail=true;g_boxes.clear();
   OnStart();CHECK(g_boxes.size()==1 && g_boxes[0].find("Calibrated 0 symbol(s)")==0 && g_boxes[0].find("1 skipped")!=string::npos && g_disk[file]==before);
   g_calc_fail=false;
   // The terminal's calculation against two sources that agree: the symbol is not calibrated,
   // and its old calibration is dropped, so Fibonacci Pro uses the agreeing values.
   g_boxes.clear();InpAllSymbols=false;_Symbol="XAUUSD";g_calc_skew["XAUUSD"]=1.5;
   OnStart();n=FPCLoad(file,list);
   CHECK(n==4 && FPCFind(list,n,"XAUUSD")<0 && FPCFind(list,n,"US100")>=0 && g_boxes.size()==1 && g_boxes[0].find("Not calibrated: XAUUSD.")!=string::npos);
   // A calculation that only the tick value disputes is trusted (the broker's tick value is the odd one out).
   g_boxes.clear();_Symbol="US100";g_syms["US100"].contract=1;
   OnStart();n=FPCLoad(file,list);u=FPCFind(list,n,"US100");
   CHECK(u>=0 && list[u].value_account==1 && g_boxes[0].find("off for: US100.")!=string::npos);
   g_calc_skew.clear();_Symbol="US100";
   // A damaged file is replaced by a fresh one rather than half-read.
   g_disk[file]="garbage";InpAllSymbols=true;g_boxes.clear();
   OnStart();n=FPCLoad(file,list);CHECK(n==4 && FPCFind(list,n,"OLD")<0 && FPCFind(list,n,"XAUUSD")>=0);
   std::printf(fails?"%d FAILED\n":"all calibration tests passed\n",fails);
   return fails?1:0;
  }
