using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Diagnostics;

public sealed class V15Preview : IDisposable {
 class Frame { public byte[] Rgb; public float[] Axes=new float[4]; public float Throttle; }
 Frame[,] data;
 string[] ids,names,notes;
 bool english;
 static readonly string[,] Translations=new string[,] {{"A 自动 13 套   ·   B 油门 15 套   ·   C 双杆 4 套     |     12 秒 / 20 FPS","A Automatic 13   ·   B Throttle 15   ·   C Dual-stick 4     |     12 s / 20 FPS"},
{"由现有 Lua 输出生成 · 65% 演示亮度 · 示意布局，非实机拍摄 · B01 使用当前配色 / 方向","Actual Lua output · 65% brightness · Simulated layout · B01 uses example settings"},
{"白点 = 物理摇杆位置 · 四轴动作示意","White dots = physical stick inputs"},
{"V15 / 全部 32 套灯效","V15 / All 32 LED Effects"},
{"第三招：同时向左 → 彩虹回旋","Combo 3: both left → rainbow swirl"},
{"第一招：向内 → 粉白星环","Combo 1: inward → pink-white nova"},
{"第二招：向外 → 冰蓝冲击","Combo 2: outward → ice-blue wave"},
{"自动循环 · 不读取摇杆","Automatic loop · No stick input"},
{"横向居中 · 等待动作","Center horizontally · Ready"},
{"粉白星环 · 动画释放","Pink-white nova · Burst playing"},
{"横向居中 · 再次准备","Center horizontally · Ready again"},
{"冰蓝冲击 · 动画释放","Ice-blue wave · Burst playing"},
{"彩虹回旋 · 动画释放","Rainbow swirl · Burst playing"},
{"A / 自动播放","A / Automatic"},
{"B / 油门联动","B / Throttle"},
{"C / 双杆联动","C / Dual-stick"},
{"第三招：同时向右","Combo 3: both sticks right"},
{"第一招：向外","Combo 1: sticks outward"},
{"回到横向中心","Return to horizontal center"},
{"第二招：向内","Combo 2: sticks inward"},
{"油门 ","Throttle "},
{"左杆","Left"},
{"右杆","Right"}};
 int count,panels,fps;
 Font code=new Font("Consolas",21,FontStyle.Bold,GraphicsUnit.Pixel);
 Font title=new Font("Microsoft YaHei",25,FontStyle.Bold,GraphicsUnit.Pixel);
 Font small=new Font("Microsoft YaHei",15,FontStyle.Regular,GraphicsUnit.Pixel);
 Font mainTitle=new Font("Microsoft YaHei",30,FontStyle.Bold,GraphicsUnit.Pixel);
 Color bg=Color.FromArgb(8,15,26), card=Color.FromArgb(18,29,46), white=Color.FromArgb(232,242,252),muted=Color.FromArgb(143,164,188);
 public V15Preview(string binary,string[] a,string[] b,string[] c,bool en){
  english=en;
  ids=a;names=b;notes=c;
  using(var br=new BinaryReader(File.OpenRead(binary))){
   count=br.ReadInt32();panels=br.ReadInt32();fps=br.ReadInt32();
   if(count!=240||panels!=32||fps!=20||ids.Length!=32)throw new Exception("Capture dimensions mismatch");
   data=new Frame[count,panels];
   for(int f=0;f<count;f++)for(int p=0;p<panels;p++){
    var frame=new Frame();frame.Rgb=br.ReadBytes(114);for(int n=0;n<4;n++)frame.Axes[n]=br.ReadSingle();frame.Throttle=br.ReadSingle();data[f,p]=frame;
   }
   if(br.BaseStream.Position!=br.BaseStream.Length)throw new Exception("Trailing binary data");
  }
 }
 void Text(Graphics g,string text,Font font,Color c,float x,float y){
  if(english)for(int i=0;i<Translations.GetLength(0);i++)text=text.Replace(Translations[i,0],Translations[i,1]);using(var brush=new SolidBrush(c))g.DrawString(text,font,brush,x,y);}
 static void Fill(Graphics g,Color c,float x,float y,float w,float h){using(var b=new SolidBrush(c))g.FillRectangle(b,x,y,w,h);}
 void Led(Graphics g,float x,float y,byte[] rgb,int id,bool key){
  int n=id*3;Color c=Color.FromArgb(rgb[n],rgb[n+1],rgb[n+2]);
  if(rgb[n]+rgb[n+1]+rgb[n+2]>0){
   foreach(int r in new[]{14,10,7})using(var b=new SolidBrush(Color.FromArgb(42,c)))g.FillEllipse(b,x-r,y-r,r*2,r*2);
  }else c=Color.FromArgb(32,45,65);
  using(var b=new SolidBrush(c)){if(key)g.FillRectangle(b,x-5,y-8,10,16);else g.FillEllipse(b,x-5,y-5,10,10);}
 }
 string ComboCue(float t){
  if(t<.4f)return "横向居中 · 等待动作";
  if(t<1.2f)return "第一招：向外";
  if(t<1.4f)return "回到横向中心";
  if(t<2.2f)return "第一招：向内 → 粉白星环";
  if(t<4.1f)return "粉白星环 · 动画释放";
  if(t<4.3f)return "横向居中 · 再次准备";
  if(t<5.1f)return "第二招：向内";
  if(t<5.3f)return "回到横向中心";
  if(t<6.1f)return "第二招：向外 → 冰蓝冲击";
  if(t<8.1f)return "冰蓝冲击 · 动画释放";
  if(t<8.3f)return "横向居中 · 再次准备";
  if(t<9.1f)return "第三招：同时向右";
  if(t<9.3f)return "回到横向中心";
  if(t<10.1f)return "第三招：同时向左 → 彩虹回旋";
  return "彩虹回旋 · 动画释放";
 }
 void Card(Graphics g,int panel,int frame){
  var f=data[frame,panel];char group=ids[panel][0];
  Color accent=group=='A'?Color.FromArgb(72,182,255):group=='B'?Color.FromArgb(80,224,166):Color.FromArgb(200,140,255);
  Fill(g,card,5,5,470,410);Fill(g,accent,5,5,4,410);
  Text(g,ids[panel],code,accent,22,17);
  Text(g,group=='A'?"A / 自动播放":group=='B'?"B / 油门联动":"C / 双杆联动",small,muted,335,20);
  Text(g,names[panel],title,white,22,53);
  using(var b=new SolidBrush(muted))g.DrawString(notes[panel],small,b,new RectangleF(22,91,430,44));
  for(int side=0;side<2;side++){
   float cx=130+side*220,cy=222;
   using(var b=new SolidBrush(bg))g.FillEllipse(b,cx-62,cy-62,124,124);
   using(var p=new Pen(Color.FromArgb(51,70,94),2)){g.DrawEllipse(p,cx-63,cy-63,126,126);g.DrawEllipse(p,cx-43,cy-43,86,86);}
   using(var p=new Pen(Color.FromArgb(83,104,129),3)){
    g.DrawLine(p,cx-22,cy,cx+22,cy);g.DrawLine(p,cx,cy-22,cx,cy+22);
    if(group=='C'){
     float sx=cx+35*f.Axes[side*2],sy=cy-35*f.Axes[side*2+1];g.DrawLine(p,cx,cy,sx,sy);
     using(var b=new SolidBrush(white))g.FillEllipse(b,sx-5,sy-5,10,10);
    }
   }
   Text(g,side==0?"左杆":"右杆",small,muted,cx-17,303);
   for(int n=0;n<16;n++){double t=(90+n*22.5)*Math.PI/180;Led(g,cx+(float)(74*Math.Cos(t)),cy+(float)(74*Math.Sin(t)),f.Rgb,side*16+n,false);}
  }
  for(int n=0;n<6;n++)Led(g,162+n*31,327,f.Rgb,32+n,true);
  if(group=='B'){
   Fill(g,Color.FromArgb(39,57,75),22,379,436,4);Fill(g,accent,22,379,436*f.Throttle,4);
   Text(g,"油门 "+Math.Round(f.Throttle*100).ToString("0")+"%  ·  0 → 100 → 0",small,muted,22,351);
  }else if(group=='C')Text(g,ids[panel]=="C04-cmb"?ComboCue((float)frame/fps):"白点 = 物理摇杆位置 · 四轴动作示意",small,muted,22,360);
  else Text(g,"自动循环 · 不读取摇杆",small,muted,22,360);
 }
 Bitmap Draw(int panel,int frame){
  var bmp=new Bitmap(panel<0?1280:480,panel<0?2368:420,PixelFormat.Format24bppRgb);
  using(var g=Graphics.FromImage(bmp)){
   g.SmoothingMode=SmoothingMode.AntiAlias;g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;g.Clear(bg);
   if(panel>=0)Card(g,panel,frame);
   else{
    Text(g,"V15 / 全部 32 套灯效",mainTitle,white,16,9);
    Text(g,"A 自动 13 套   ·   B 油门 15 套   ·   C 双杆 4 套     |     12 秒 / 20 FPS",small,muted,18,52);
    for(int i=0;i<32;i++){
     var state=g.Save();g.TranslateTransform((i%4)*320,88+(i/4)*280);g.ScaleTransform(2f/3,2f/3);Card(g,i,frame);g.Restore(state);
    }
    Text(g,"由现有 Lua 输出生成 · 65% 演示亮度 · 示意布局，非实机拍摄 · B01 使用当前配色 / 方向",small,muted,18,2344);
   }
  }
  return bmp;
 }
 public void Sample(string file,int panel,int frame){using(var bmp=Draw(panel,frame))bmp.Save(file,ImageFormat.Png);}
 public void PaletteSample(string file){
  using(var bmp=new Bitmap(1024,512,PixelFormat.Format24bppRgb)){
   for(int i=0;i<1024*512;i++){
    int f=(i/38)%count,p=(i/(38*count))%panels,n=i%38;
    var rgb=data[f,p].Rgb;Color c=Color.FromArgb(rgb[n*3],rgb[n*3+1],rgb[n*3+2]);
    if(i%7==0)c=bg;else if(i%7==1)c=card;else if(i%11==0)c=white;else if(i%13==0)c=muted;
    bmp.SetPixel(i%1024,i/1024,c);
   }
   bmp.Save(file,ImageFormat.Png);
  }
 }
 public void Encode(string ffmpeg,string palette,string output,int panel){
  Directory.CreateDirectory(Path.GetDirectoryName(output));
  var psi=new ProcessStartInfo(ffmpeg){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,RedirectStandardInput=true,RedirectStandardError=true};
  foreach(string a in new[]{"-hide_banner","-loglevel","error","-f","image2pipe","-framerate",fps.ToString(),"-vcodec","bmp","-i","pipe:0","-i",palette,"-filter_complex","[0:v][1:v]paletteuse=dither=none","-loop","0","-y",output})psi.ArgumentList.Add(a);
  using(var proc=Process.Start(psi)){
   var err=proc.StandardError.ReadToEndAsync();
   using(var memory=new MemoryStream())for(int frame=0;frame<count;frame++){
    using(var bmp=Draw(panel,frame)){memory.SetLength(0);bmp.Save(memory,ImageFormat.Bmp);memory.WriteTo(proc.StandardInput.BaseStream);}
   }
   proc.StandardInput.Close();proc.WaitForExit();string errors=err.GetAwaiter().GetResult();
   if(proc.ExitCode!=0)throw new Exception("FFmpeg: "+errors);
  }
 }
 public void Dispose(){code.Dispose();title.Dispose();small.Dispose();mainTitle.Dispose();}
}
