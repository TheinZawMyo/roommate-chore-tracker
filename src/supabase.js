import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://dysghrcllkvbjhhgjvwh.supabase.co'
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5c2docmNsbGt2YmpoaGdqdndoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzExNzUzODksImV4cCI6MjA4Njc1MTM4OX0.09f9BIcHWP-_ioToEw-uoCu7u4XXq_2aN_zKq3uVAVY'

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
