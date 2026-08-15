const express=require("express");const app=express();
app.get("/",(req,res)=>res.send("Merhaba — ağır test API"));
app.get("/health",(req,res)=>res.json({ok:true,ts:Date.now()}));
app.get("/api/time",(req,res)=>res.json({time:new Date().toISOString()}));
app.listen(3000,()=>console.log("http://localhost:3000"));
