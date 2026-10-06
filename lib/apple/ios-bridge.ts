export type IOSPurchaseResult = {
  success: boolean
  signedTransaction?: string
  productID?: string
  message?: string
}

type IOSMessageHandler = {
  postMessage: (message: unknown) => void
}

type IOSWindow = Window & {
  __SYNTAX_COACH_IOS__?: boolean
  __syntaxCoachApplePurchaseResult?: (result: IOSPurchaseResult) => void
  __syntaxCoachAppleRestoreResult?: (result: IOSPurchaseResult) => void
  webkit?: {
    messageHandlers?: {
      syntaxCoach?: IOSMessageHandler
    }
  }
}

declare global {
  interface Window {
    __SYNTAX_COACH_IOS__?: boolean
    __syntaxCoachApplePurchaseResult?: (result: IOSPurchaseResult) => void
    __syntaxCoachAppleRestoreResult?: (result: IOSPurchaseResult) => void
  }
}

function getIOSWindow() {
  if (typeof window === 'undefined') return null
  return window as IOSWindow
}

export function isIOSApp() {
  const currentWindow = getIOSWindow()
  return Boolean(currentWindow?.__SYNTAX_COACH_IOS__ || currentWindow?.webkit?.messageHandlers?.syntaxCoach)
}

export function sendIOSMessage(message: Record<string, unknown>) {
  getIOSWindow()?.webkit?.messageHandlers?.syntaxCoach?.postMessage(message)
}
