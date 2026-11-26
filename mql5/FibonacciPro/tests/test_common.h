// Shared fakes for the behavioural tests (indicator and calibration script): chart objects,
// the clock, alerts, files in memory, the string/math runtime and a market (symbols with
// quotes and contract specifications, and the trading account).
#pragma once
#include <cstdio>
#include <cstring>
#include <map>
#include <algorithm>
#include <cstdlib>
#include <array>
#include <vector>
static int g_sets_int=0,g_sets_str=0,g_creates=0,g_deletes=0;static std::map<string,bool> g_objs;static std::map<string,string> g_texts;
bool ObjectCreate(long,const string& n,ENUM_OBJECT,int,datetime,double){g_creates++;g_objs[n]=true;return true;}
bool ObjectDelete(long,const string& n){g_deletes++;g_objs.erase(n);return true;}
int ObjectsDeleteAll(long,const string& p,int,int){int k=0;for(auto it=g_objs.begin();it!=g_objs.end();){if(it->first.rfind(p,0)==0){it=g_objs.erase(it);k++;}else ++it;}return k;}
int ObjectFind(long,const string& n){return g_objs.count(n)?0:-1;}
bool ObjectSetInteger(long,const string&,ENUM_OBJECT_PROPERTY_INTEGER,long){g_sets_int++;return true;}
bool ObjectSetString(long,const string& n,ENUM_OBJECT_PROPERTY_STRING p,const string& v){g_sets_str++;if(p==OBJPROP_TEXT)g_texts[n]=v;return true;}
string ObjectGetString(long,const string& n,ENUM_OBJECT_PROPERTY_STRING,int){auto it=g_texts.find(n);return it==g_texts.end()?"":it->second;}
static datetime g_test_now=0;
datetime TimeTradeServer(){return g_test_now;}datetime TimeGMT(){return g_test_now-2*3600;}datetime TimeCurrent(){return g_test_now;}datetime TimeLocal(){return g_test_now;}
static std::map<string,double> g_gv;static int g_sounds=0,g_pushes=0;
bool PlaySound(const string&){g_sounds++;return true;}bool SendNotification(const string&){g_pushes++;return true;}
bool GlobalVariableTemp(const string& n){if(g_gv.count(n))return false;g_gv[n]=0;return true;}
bool GlobalVariableSetOnCondition(const string& n,double v,double c){auto it=g_gv.find(n);if(it==g_gv.end() || it->second!=c)return false;it->second=v;return true;}
// In-memory files (1 byte per character).
struct MemFile{string name,data;size_t pos=0;bool write=false;};
static std::map<string,string> g_disk;static std::map<int,MemFile> g_open;static int g_next_handle=1;
// MetaTrader's Common folder (FILE_COMMON), shared by every terminal, is its own namespace.
static string DiskKey(const string& n,int common){return (common&FILE_COMMON)?"<Common>\\"+n:n;}
int FileOpen(const string& n0,int flags,short,uint)
  {string n=DiskKey(n0,flags);MemFile f;f.name=n;f.write=(flags&FILE_WRITE)!=0;if(!f.write){auto it=g_disk.find(n);if(it==g_disk.end())return INVALID_HANDLE;f.data=it->second;}g_open[g_next_handle]=f;return g_next_handle++;}
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
bool FileIsExist(const string& n,int c){return g_disk.count(DiskKey(n,c))>0;}
// As in MT5: the source in the common folder with common=FILE_COMMON, the destination with
// FILE_COMMON in mode; an existing destination needs FILE_REWRITE.
bool FileCopy(const string& a0,int c,const string& b0,int m)
  {string a=DiskKey(a0,c),b=DiskKey(b0,m);if(!g_disk.count(a) || (g_disk.count(b) && !(m&FILE_REWRITE)))return false;g_disk[b]=g_disk[a];return true;}
bool FileMove(const string& a0,int c,const string& b0,int m)
  {string a=DiskKey(a0,c),b=DiskKey(b0,m);if(!g_disk.count(a) || (g_disk.count(b) && !(m&FILE_REWRITE)))return false;string d=g_disk[a];g_disk.erase(a);g_disk[b]=d;return true;}
bool FileDelete(const string& n,int c){return g_disk.erase(DiskKey(n,c))>0;}
// Files of one folder matching a pattern with '*' (sub-folders are not listed).
static bool Glob(const string& p,const string& s)
  {
   size_t star=p.find('*');
   if(star==string::npos)return p==s;
   string head=p.substr(0,star),tail=p.substr(star+1);
   if(s.size()<head.size() || s.compare(0,head.size(),head)!=0)return false;
   for(size_t i=head.size();i<=s.size();i++)if(Glob(tail,s.substr(i)))return true;
   return false;
  }
static std::map<long,std::vector<string>> g_finds;static long g_next_find=100;
long FileFindFirst(const string& filter,string& name,int c)
  {
   string f=DiskKey(filter,c);
   size_t cut=f.rfind('\\');
   string dir=cut==string::npos?"":f.substr(0,cut+1),pat=cut==string::npos?f:f.substr(cut+1);
   std::vector<string> hits;
   for(auto& kv:g_disk)
     {
      if(kv.first.size()<=dir.size() || kv.first.compare(0,dir.size(),dir)!=0)continue;
      string rest=kv.first.substr(dir.size());
      if(rest.find('\\')==string::npos && Glob(pat,rest))hits.push_back(rest);
     }
   if(hits.empty())return INVALID_HANDLE;
   name=hits[0];hits.erase(hits.begin());
   long h=g_next_find++;g_finds[h]=hits;return h;
  }
bool FileFindNext(long h,string& name){auto it=g_finds.find(h);if(it==g_finds.end() || it->second.empty())return false;name=it->second[0];it->second.erase(it->second.begin());return true;}
void FileFindClose(long h){g_finds.erase(h);}
uint FileWriteArray(int h,MQLArr<uchar>& a,int start,int count)
  {
   if(count<0)count=(int)a.v.size()-start;
   if(start<0 || count<0 || start+count>(int)a.v.size())return 0;
   if(count>0)g_open[h].data.append((const char*)a.v.data()+start,(size_t)count);
   return (uint)count;
  }
uint FileReadArray(int h,MQLArr<uchar>& a,int start,int count)
  {
   MemFile& f=g_open[h];
   size_t avail=f.pos<f.data.size()?f.data.size()-f.pos:0;
   size_t n=count<0?avail:std::min((size_t)count,avail);
   if(start<0)return 0;
   if(a.v.size()<(size_t)start+n)a.v.resize((size_t)start+n);
   if(n>0)std::memcpy(a.v.data()+start,f.data.data()+f.pos,n);
   f.pos+=n;return (uint)n;
  }
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
// ---- market: symbols, quotes, contract specifications and the account
struct FakeSym{string base,profit;long mode;double bid,ask,point,tick,tick_value,tick_loss,contract,vmin,vmax,vstep;int digits;bool watch;};
static std::map<string,FakeSym> g_syms;static std::vector<string> g_all,g_watch;static int g_selects=0;
static string g_acc_ccy="USD",g_server="";static long g_login=0;static double g_balance=10000,g_equity=10000;
long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER){return g_login;}
string AccountInfoString(ENUM_ACCOUNT_INFO_STRING p){return p==ACCOUNT_CURRENCY?g_acc_ccy:g_server;}
double AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE p){return p==ACCOUNT_BALANCE?g_balance:g_equity;}
double SymbolInfoDouble(const string& n,ENUM_SYMBOL_INFO_DOUBLE p)
  {
   auto it=g_syms.find(n);if(it==g_syms.end())return 0;const FakeSym& s=it->second;
   switch(p)
     {
      case SYMBOL_BID:return s.bid;case SYMBOL_ASK:return s.ask;case SYMBOL_POINT:return s.point;case SYMBOL_TRADE_TICK_SIZE:return s.tick;
      case SYMBOL_TRADE_TICK_VALUE:return s.tick_value;case SYMBOL_TRADE_TICK_VALUE_LOSS:return s.tick_loss;case SYMBOL_TRADE_TICK_VALUE_PROFIT:return s.tick_value;
      case SYMBOL_TRADE_CONTRACT_SIZE:return s.contract;case SYMBOL_VOLUME_MIN:return s.vmin;case SYMBOL_VOLUME_MAX:return s.vmax;case SYMBOL_VOLUME_STEP:return s.vstep;
     }
   return 0;
  }
long SymbolInfoInteger(const string& n,ENUM_SYMBOL_INFO_INTEGER p)
  {auto it=g_syms.find(n);if(it==g_syms.end())return 0;return p==SYMBOL_DIGITS?it->second.digits:(p==SYMBOL_TRADE_CALC_MODE?it->second.mode:(it->second.watch?1:0));}
string SymbolInfoString(const string& n,ENUM_SYMBOL_INFO_STRING p)
  {auto it=g_syms.find(n);if(it==g_syms.end())return "";return p==SYMBOL_CURRENCY_BASE?it->second.base:it->second.profit;}
int SymbolsTotal(bool selected){return (int)(selected?g_watch.size():g_all.size());}
string SymbolName(int i,bool selected){const std::vector<string>& v=selected?g_watch:g_all;return i>=0 && i<(int)v.size()?v[i]:string();}
bool SymbolSelect(const string& n,bool on)
  {auto it=g_syms.find(n);if(it==g_syms.end())return false;g_selects++;if(on && !it->second.watch){it->second.watch=true;g_watch.push_back(n);}return true;}
// tick_value: the broker's figure for one tick on 1.00 lot, in the account currency (may be wrong on purpose).
static void AddSym(const string& n,const string& base,const string& profit,long mode,double bid,double ask,int digits,double tick,double tick_value,double contract,bool watch,
                   double vmin=0.01,double vmax=100,double vstep=0.01)
  {
   FakeSym s;s.base=base;s.profit=profit;s.mode=mode;s.bid=bid;s.ask=ask;s.digits=digits;s.point=std::pow(10.0,-digits);s.tick=tick;
   s.tick_value=tick_value;s.tick_loss=tick_value;s.contract=contract;s.vmin=vmin;s.vmax=vmax;s.vstep=vstep;s.watch=watch;
   if(!g_syms.count(n))g_all.push_back(n);
   g_syms[n]=s;
   if(watch && std::find(g_watch.begin(),g_watch.end(),n)==g_watch.end())g_watch.push_back(n);
  }
static void ClearMarket(){g_syms.clear();g_all.clear();g_watch.clear();g_selects=0;}
