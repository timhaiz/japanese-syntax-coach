import './globals.css'
import './profile.css'
import './header.css'
import './tasks.css'
import './analysis.css'
import type {ReactNode} from 'react'
export const metadata={title:'句型教练｜标准日本语',description:'把句型练成反射',manifest:'/manifest.webmanifest'}
export default function Layout({children}:{children:ReactNode}){return <html lang="zh-CN"><body>{children}</body></html>}
