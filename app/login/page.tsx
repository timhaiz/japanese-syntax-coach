'use client'
import {useState} from 'react'
import {getSupabaseBrowser} from '@/lib/supabase'
import '../auth.css'

type AuthMode='login'|'register'|'verify'

export default function Login(){
 const [mode,setMode]=useState<AuthMode>('login')
 const [email,setEmail]=useState('')
 const [password,setPassword]=useState('')
 const [confirmPassword,setConfirmPassword]=useState('')
 const [code,setCode]=useState('')
 const [pendingEmail,setPendingEmail]=useState('')
 const [busy,setBusy]=useState(false)
 const [message,setMessage]=useState('')
 const [error,setError]=useState('')
 const supabase=getSupabaseBrowser()
 const clearFeedback=()=>{setMessage('');setError('')}
 const switchMode=(next:AuthMode)=>{setMode(next);setPassword('');setConfirmPassword('');setCode('');clearFeedback()}
 const submitLogin=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail||!password){setError('请输入邮箱和密码。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {error:authError}=await supabase.auth.signInWithPassword({email:normalizedEmail,password});setBusy(false);if(authError){setError('邮箱或密码不正确，请检查后重试。');return}location.href='/'}
 const submitRegister=async()=>{clearFeedback();const normalizedEmail=email.trim().toLowerCase();if(!normalizedEmail||!password){setError('请输入邮箱和密码。');return}if(password.length<6){setError('密码至少需要 6 位。');return}if(password!==confirmPassword){setError('两次输入的密码不一致。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {error:authError}=await supabase.auth.signUp({email:normalizedEmail,password,options:{emailRedirectTo:`${location.origin}/auth/callback`}});setBusy(false);if(authError){setError(authError.message);return}setPendingEmail(normalizedEmail);setMode('verify');setMessage(`验证码已发送到 ${normalizedEmail}，请输入邮件中的 6 位验证码。`)}
 const verifySignup=async()=>{clearFeedback();const normalizedCode=code.trim();if(!pendingEmail||!normalizedCode){setError('请输入邮箱中的验证码。');return}if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}setBusy(true);const {data,error:authError}=await supabase.auth.verifyOtp({email:pendingEmail,token:normalizedCode,type:'signup'});setBusy(false);if(authError){setError('验证码无效或已过期，请重新获取。');return}if(data.session){location.href='/';return}setMode('login');setEmail(pendingEmail);setMessage('邮箱验证成功，请使用刚才设置的密码登录。')}
 const resendSignupCode=async()=>{clearFeedback();if(!supabase){setError('尚未配置 Supabase，请先填写环境变量。');return}if(!pendingEmail||!password){setError('请返回注册页重新填写密码。');return}setBusy(true);const {error:authError}=await supabase.auth.signUp({email:pendingEmail,password,options:{emailRedirectTo:`${location.origin}/auth/callback`}});setBusy(false);if(authError)setError(authError.message);else setMessage(`验证码已重新发送到 ${pendingEmail}。`)}
 return <main className="auth"><div className="auth-card"><div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>标准日本语 · 上册</small></div></div><h1>把句型练成反射。</h1><p className="muted">登录后同步你的学习进度、错题和复习日历。</p>{mode!=='verify'&&<div className="auth-tabs"><button className={mode==='login'?'active':''} onClick={()=>switchMode('login')}>登录</button><button className={mode==='register'?'active':''} onClick={()=>switchMode('register')}>注册</button></div>}{mode==='verify'?<><div className="auth-step"><span>1</span><div><b>确认邮箱</b><small>{pendingEmail}</small></div></div><input value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,'').slice(0,6))} placeholder="输入 6 位验证码" inputMode="numeric" autoComplete="one-time-code"/><button className="primary wide" onClick={verifySignup} disabled={busy}>{busy?'验证中…':'验证邮箱并继续 →'}</button><button className="text-button" onClick={resendSignupCode} disabled={busy}>重新发送验证码</button><button className="text-button" onClick={()=>switchMode('register')}>返回修改邮箱</button></>:mode==='login'?<><input value={email} onChange={e=>{setEmail(e.target.value);clearFeedback()}} placeholder="邮箱" type="email" autoComplete="email"/><input value={password} onChange={e=>{setPassword(e.target.value);clearFeedback()}} placeholder="密码" type="password" autoComplete="current-password"/><button className="primary wide" onClick={submitLogin} disabled={busy}>{busy?'登录中…':'登录 →'}</button></>:<><input value={email} onChange={e=>{setEmail(e.target.value);clearFeedback()}} placeholder="邮箱" type="email" autoComplete="email"/><input value={password} onChange={e=>{setPassword(e.target.value);clearFeedback()}} placeholder="设置密码（至少 6 位）" type="password" autoComplete="new-password"/><input value={confirmPassword} onChange={e=>{setConfirmPassword(e.target.value);clearFeedback()}} placeholder="再次输入密码" type="password" autoComplete="new-password"/><button className="primary wide" onClick={submitRegister} disabled={busy}>{busy?'发送中…':'注册并获取验证码 →'}</button></>}{message&&<div className="success">{message}</div>}{error&&<p className="error">{error}</p>}<a href="/">先看看学习界面</a></div></main>
}
