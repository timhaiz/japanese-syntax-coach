import { NextResponse } from 'next/server'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

const allowedTypes = new Set(['signup', 'invite', 'recovery', 'email_change'])

export async function GET(request: Request) {
  const url = new URL(request.url)
  const error = url.searchParams.get('error')
  const errorCode = url.searchParams.get('error_code')
  const errorDescription = url.searchParams.get('error_description')
  const next = url.searchParams.get('next') === '/reset-password' ? '/reset-password' : '/'

  if (error || errorCode) {
    const loginURL = new URL('/login', url.origin)
    loginURL.searchParams.set('error', errorCode || error || 'auth_failed')
    if (errorDescription) loginURL.searchParams.set('description', errorDescription)
    return NextResponse.redirect(loginURL)
  }

  const code = url.searchParams.get('code')
  const tokenHash = url.searchParams.get('token_hash')
  const typeParam = url.searchParams.get('type') || 'signup'
  const type = allowedTypes.has(typeParam) ? typeParam as 'signup' | 'invite' | 'recovery' | 'email_change' : 'signup'

  if (code || tokenHash) {
    const store = await cookies()
    const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (items) => {
          try { items.forEach(({ name, value, options }) => store.set(name, value, options)) } catch { /* read-only response */ }
        },
      },
    })
    const result = code
      ? await supabase.auth.exchangeCodeForSession(code)
      : await supabase.auth.verifyOtp({ token_hash: tokenHash!, type })
    if (result.error) {
      const loginURL = new URL('/login', url.origin)
      loginURL.searchParams.set('error', 'callback_failed')
      loginURL.searchParams.set('description', result.error.message)
      return NextResponse.redirect(loginURL)
    }
  }

  return NextResponse.redirect(new URL(next, url.origin))
}
