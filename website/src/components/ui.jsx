import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva } from 'class-variance-authority'
import { cn } from '../lib/utils'

const buttonVariants = cva('inline-flex items-center justify-center whitespace-nowrap rounded-full text-sm font-extrabold transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cineo focus-visible:ring-offset-2 focus-visible:ring-offset-ink disabled:pointer-events-none disabled:opacity-50', {
  variants: {
    variant: {
      default: 'bg-cineo text-[#251300] shadow-glow-sm hover:bg-cineo-light hover:-translate-y-0.5',
      outline: 'border border-line bg-transparent text-copy hover:border-cineo/60 hover:bg-cineo/10',
      ghost: 'text-muted hover:bg-panel2 hover:text-copy',
      dark: 'bg-panel2 text-copy hover:bg-line',
    },
    size: {
      default: 'h-12 px-5',
      sm: 'h-10 px-4 text-xs',
      lg: 'h-14 px-7 text-base',
      icon: 'h-11 w-11',
    },
  },
  defaultVariants: { variant: 'default', size: 'default' },
})

export function Button({ className, variant, size, asChild = false, ...props }) {
  const Comp = asChild ? Slot : 'button'
  return <Comp className={cn(buttonVariants({ variant, size, className }))} {...props} />
}

export function Badge({ className, children, ...props }) {
  return <span className={cn('inline-flex items-center rounded-full border border-cineo/30 bg-cineo/10 px-3 py-1 text-[11px] font-extrabold uppercase tracking-[0.18em] text-cineo-light', className)} {...props}>{children}</span>
}

export function Card({ className, ...props }) {
  return <div className={cn('rounded-[1.5rem] border border-line/80 bg-panel', className)} {...props} />
}

export function Separator({ className, ...props }) {
  return <div role="separator" className={cn('h-px w-full bg-line/70', className)} {...props} />
}
