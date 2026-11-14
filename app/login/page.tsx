'use client'
import {useEffect, useState} from 'react'
import {getSupabaseBrowser} from '@/lib/supabase'
import '../auth.css'

type AuthMode='login'|'register'|'reset'

export default function Login(){
 const [mode,setMode]=useState<AuthMode>('login')
 const [email,setEmail]=useState('')
 const [password,setPassword]=useState('')
 const [confirmPassword,setConfirmPassword]=useState('')
 const [code,setCode]=useState('')
 const [codeSent,setCodeSent]=useState(false)
 const [countdown,setCountdown]=useState(0)
 const [sendingCode,setSendingCode]=useState(false)
 const [busy,setBusy]=useState(false)
 const [message,setMessage]=useState('')
 const [error,setError]=useState('')
 const supabase=getSupabaseBrowser()
 useEffect(()=>{
  const params=new URLSearchParams(location.search)
  const authError=params.get('error')
  const description=params.get('description')
  if(authError){
   const messages:Record<string,string>={provider_disabled:'Apple 登录尚未在 Supabase 中启用。',callback_failed:'登录回调失败，请重试。'}
   setError(description||messages[authError]||'登录失败，请重试。')
  }
 },[])
 useEffect(()=>{
  if(countdown<=0)return
  const timer=window.setTimeout(()=>setCountdown(value=>Math.max(0,value-1)),1000)
  return ()=>window.clearTimeout(timer)
 },[countdown])
 const clearFeedback=()=>{setMessage('');setError('')}
 const switchMode=(next:AuthMode)=>{setMode(next);setPassword('');setConfirmPassword('');setCode('');setCodeSent(false);setCountdown(0);clearFeedback()}
 const submitLogin=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail||!password){setError('请输入邮箱和密码。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {error:authError}=await supabase.auth.signInWithPassword({email:normalizedEmail,password});setBusy(false);if(authError){setError('邮箱或密码不正确，请检查后重试。');return}location.href='/'}
 const sendSignupCode=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail||!password){setError('请先输入邮箱和密码。');return}if(password.length<6){setError('密码至少需要 6 位。');return}if(password!==confirmPassword){setError('两次输入的密码不一致。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setSendingCode(true);const {error:authError}=await supabase.auth.signUp({email:normalizedEmail,password,options:{emailRedirectTo:`${location.origin}/auth/callback`}});setSendingCode(false);if(authError){setError(authError.message);return}setCodeSent(true);setCountdown(60);setMessage(`验证码已发送到 ${normalizedEmail}，请输入邮件中的 6 位验证码后提交注册。`)}
 const submitRegister=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail||!password){setError('请输入邮箱和密码。');return}if(password.length<6){setError('密码至少需要 6 位。');return}if(password!==confirmPassword){setError('两次输入的密码不一致。');return}const normalizedCode=code.trim();if(normalizedCode.length!==6){setError('请先获取并输入 6 位验证码。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {data,error:authError}=await supabase.auth.verifyOtp({email:normalizedEmail,token:normalizedCode,type:'signup'});setBusy(false);if(authError){setError('验证码无效或已过期，请重新获取。');return}if(data.session){location.href='/';return}setMode('login');setEmail(normalizedEmail);setMessage('注册并验证成功，请使用刚才设置的密码登录。')}
 const requestPasswordSetup=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail){setError('请输入需要设置密码的邮箱。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {error:authError}=await supabase.auth.resetPasswordForEmail(normalizedEmail,{redirectTo:`${location.origin}/auth/callback?next=/reset-password`});setBusy(false);if(authError)setError(authError.message);else setMessage(`设置密码邮件已发送到 ${normalizedEmail}。`)}
 const signInWithApple=async()=>{clearFeedback();if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {error:authError}=await supabase.auth.signInWithOAuth({provider:'apple',options:{redirectTo:`${location.origin}/auth/callback`}});if(authError){setBusy(false);setError('Apple 登录暂未配置，请稍后再试。')}}
 return <main className="auth"><div className="auth-card"><div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>新版标准日本语 · 初级上册</small></div></div><h1>把句型练成反射。</h1><p className="muted">登录后同步你的课程进度、错题和复习日历。</p>{mode!=='reset'&&<div className="auth-tabs"><button className={mode==='login'?'active':''} onClick={()=>switchMode('login')}>登录</button><button className={mode==='register'?'active':''} onClick={()=>switchMode('register')}>注册</button></div>}{mode==='reset'?<><p className="auth-help">旧账号没有密码？输入注册邮箱，我们会发送一封仅用于设置密码的邮件。</p><input value={email} onChange={e=>{setEmail(e.target.value);clearFeedback()}} placeholder="邮箱" type="email" autoComplete="email"/><button className="primary wide" onClick={requestPasswordSetup} disabled={busy}>{busy?'发送中…':'发送设置密码邮件 →'}</button><button className="text-button" onClick={()=>switchMode('login')}>返回登录</button></>:mode==='login'?<><input value={email} onChange={e=>{setEmail(e.target.value);clearFeedback()}} placeholder="邮箱" type="email" autoComplete="email"/><input value={password} onChange={e=>{setPassword(e.target.value);clearFeedback()}} placeholder="密码" type="password" autoComplete="current-password"/><button className="primary wide" onClick={submitLogin} disabled={busy}>{busy?'登录中…':'登录 →'}</button><button className="text-button" onClick={()=>switchMode('reset')}>忘记密码</button><button className="apple-button" onClick={signInWithApple} disabled={busy}>使用 Apple 登录</button></>:<><input value={email} onChange={e=>{setEmail(e.target.value);clearFeedback()}} placeholder="邮箱" type="email" autoComplete="email"/><input value={password} onChange={e=>{setPassword(e.target.value);clearFeedback()}} placeholder="设置密码（至少 6 位）" type="password" autoComplete="new-password"/><input value={confirmPassword} onChange={e=>{setConfirmPassword(e.target.value);clearFeedback()}} placeholder="再次输入密码" type="password" autoComplete="new-password"/><div className="auth-code-row"><input value={code} onChange={e=>{setCode(e.target.value.replace(/\D/g,'').slice(0,6));clearFeedback()}} placeholder="输入 6 位验证码" inputMode="numeric" autoComplete="one-time-code"/><button type="button" className="code-button" onClick={sendSignupCode} disabled={busy||sendingCode||countdown>0}>{sendingCode?'发送中…':countdown>0?`${countdown}s 后重发`:codeSent?'重新获取':'获取验证码'}</button></div><button className="primary wide" onClick={submitRegister} disabled={busy||sendingCode}>{busy?'提交中…':'提交注册'}</button></>}{message&&<div className="success">{message}</div>}{error&&<p className="error">{error}</p>}<p className="auth-legal">继续使用即表示你同意<a href="/terms">用户协议</a>和<a href="/privacy">隐私政策</a>。</p><a href="/">先看看学习界面</a></div></main>
}
