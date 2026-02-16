<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { 
  ChevronLeft, 
  ChevronRight, 
  CheckCircle2, 
  Circle, 
  ArrowLeftRight,
  TrendingUp,
  Calendar,
  User as UserIcon,
  Loader2,
  Soup as ChefIcon,
  Clock
} from 'lucide-vue-next'
import { supabase } from './supabase'

// --- Constants & Helper Functions ---
const START_DATE = new Date('2026-02-09') // A Monday
const ROOMMATES_COUNT = 5

const getMonday = (d) => {
  d = new Date(d)
  const day = d.getDay()
  const diff = d.getDate() - day + (day === 0 ? -6 : 1)
  const Monday = new Date(d.setDate(diff))
  Monday.setHours(0, 0, 0, 0)
  return Monday
}

const formatDate = (date) => {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

// --- State ---
const currentMonday = ref(getMonday(new Date()))
const roommates = ref([])
const rotationEntries = ref([]) // Hold multiple weeks for schedule accuracy
const loading = ref(true)
const syncing = ref(false)
const showSwapModal = ref(false)

// --- Computed ---
const weeksSinceStart = computed(() => {
  const diff = currentMonday.value.getTime() - START_DATE.getTime()
  return Math.floor(diff / (7 * 24 * 60 * 60 * 1000))
})

const defaultCleanerIndex = computed(() => {
  // Use modulo with support for negative numbers if navigating back before START_DATE
  const index = weeksSinceStart.value % ROOMMATES_COUNT
  return index < 0 ? index + ROOMMATES_COUNT : index
})

const currentCleaner = computed(() => {
  const dateStr = formatDateToSql(currentMonday.value)
  const entry = rotationEntries.value.find(e => e.week_start_date === dateStr)
  
  if (entry?.roommate_id) {
    return roommates.value.find(r => r.id === entry.roommate_id)
  }
  return roommates.value.find(r => r.order_index === defaultCleanerIndex.value)
})

const rotationEntry = computed(() => {
  const dateStr = formatDateToSql(currentMonday.value)
  return rotationEntries.value.find(e => e.week_start_date === dateStr) || null
})

const upcomingSchedule = computed(() => {
  if (roommates.value.length === 0) return []
  
  return Array.from({ length: 4 }).map((_, i) => {
    const weekOffset = i + 1
    const weekDate = new Date(currentMonday.value)
    weekDate.setDate(weekDate.getDate() + (weekOffset * 7))
    
    const index = (weeksSinceStart.value + weekOffset) % ROOMMATES_COUNT
    const normalizedIndex = index < 0 ? index + ROOMMATES_COUNT : index
    
    // Check for swap override in database
    const weekDateStr = formatDateToSql(weekDate)
    const entry = rotationEntries.value.find(e => e.week_start_date === weekDateStr)
    
    const cleaner = entry?.roommate_id 
      ? roommates.value.find(r => r.id === entry.roommate_id)
      : roommates.value.find(r => r.order_index === normalizedIndex)
    
    return {
      date: weekDate,
      cleaner,
      isSwapped: !!entry?.swapped_from_id
    }
  })
})

const formatDateToSql = (date) => {
  const yyyy = date.getFullYear()
  const mm = String(date.getMonth() + 1).padStart(2, '0')
  const dd = String(date.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

const cookingSchedule = computed(() => {
  if (roommates.value.length === 0) return []
  
  const schedule = [
    { day: 'Monday', name: 'Nay Htet Oo' },
    { day: 'Tuesday', name: 'Aung Soe Oo' },
    { day: 'Wednesday', name: 'Thant Zin Htun' },
    { day: 'Thursday', name: 'Myint Myat Thu' },
    { day: 'Friday', name: 'Thein Zaw Myo' }
  ]
  
  return schedule.map(item => {
    const chef = roommates.value.find(r => r.name === item.name)
    return {
      day: item.day,
      chef: chef || { name: item.name }
    }
  })
})

const isCurrentWeek = computed(() => {
  return currentMonday.value.getTime() === getMonday(new Date()).getTime()
})

// --- Methods ---
const fetchData = async () => {
  loading.value = true
  try {
    // 1. Fetch Roommates if not already fetched
    if (roommates.value.length === 0) {
      const { data: rmData, error: rmError } = await supabase
        .from('roommates')
        .select('*')
        .order('order_index', { ascending: true })
      
      if (rmError) throw rmError
      roommates.value = rmData
    }

    // 2. Fetch Rotations for range (Current week + 5 future weeks to detect trades)
    const startDateStr = formatDateToSql(currentMonday.value)
    const endDate = new Date(currentMonday.value)
    endDate.setDate(endDate.getDate() + 35)
    const endDateStr = formatDateToSql(endDate)

    const { data: rotData, error: rotError } = await supabase
      .from('chore_rotations')
      .select('*')
      .gte('week_start_date', startDateStr)
      .lte('week_start_date', endDateStr)

    if (rotError) throw rotError
    rotationEntries.value = rotData || []
  } catch (err) {
    console.error('Error fetching data:', err)
  } finally {
    loading.value = false
  }
}

const toggleComplete = async () => {
  if (!currentCleaner.value) return
  syncing.value = true
  
  const dateStr = formatDateToSql(currentMonday.value)
  const isCompleted = !rotationEntry.value?.is_completed

  try {
    if (rotationEntry.value) {
      const { data, error } = await supabase
        .from('chore_rotations')
        .update({ is_completed: isCompleted })
        .eq('id', rotationEntry.value.id)
        .select()
        .single()
      
      if (error) throw error
      // Update local array
      const idx = rotationEntries.value.findIndex(e => e.id === data.id)
      if (idx !== -1) rotationEntries.value[idx] = data
    } else {
      const { data, error } = await supabase
        .from('chore_rotations')
        .insert({
          week_start_date: dateStr,
          roommate_id: currentCleaner.value.id,
          is_completed: isCompleted
        })
        .select()
        .single()
      
      if (error) throw error
      rotationEntries.value.push(data)
    }
  } catch (err) {
    console.error('Error updating status:', err)
  } finally {
    syncing.value = false
  }
}

const swapCleaner = async (newCleanerId) => {
  syncing.value = true
  const dateStr = formatDateToSql(currentMonday.value)
  
  // 1. Identify Roommates
  const originalCleaner = roommates.value.find(r => r.order_index === defaultCleanerIndex.value)
  const targetRoommate = roommates.value.find(r => r.id === newCleanerId)
  
  if (!originalCleaner || !targetRoommate) return

  // 2. Calculate the Target's original scheduled week
  const currentIndex = defaultCleanerIndex.value
  const targetIndex = targetRoommate.order_index
  const distance = (targetIndex - currentIndex + 5) % 5
  
  if (distance === 0) {
    showSwapModal.value = false
    syncing.value = false
    return
  }

  const targetWeekDate = new Date(currentMonday.value)
  targetWeekDate.setDate(targetWeekDate.getDate() + (distance * 7))
  const targetWeekStr = formatDateToSql(targetWeekDate)

  try {
    // 3. Perform TWO-WAY swap in chore_rotations table
    // A. Target roommate takes current week
    const { error: err1 } = await supabase.from('chore_rotations').upsert({
      week_start_date: dateStr,
      roommate_id: targetRoommate.id,
      swapped_from_id: originalCleaner.id
    }, { onConflict: 'week_start_date' })
    if (err1) throw err1

    // B. Original roommate takes target's original future week
    const { error: err2 } = await supabase.from('chore_rotations').upsert({
      week_start_date: targetWeekStr,
      roommate_id: originalCleaner.id,
      swapped_from_id: targetRoommate.id
    }, { onConflict: 'week_start_date' })
    if (err2) throw err2

    // 4. Refresh local state
    await fetchData()
    showSwapModal.value = false
  } catch (err) {
    console.error('Error swapping shifts:', err)
  } finally {
    syncing.value = false
  }
}

const navigateWeek = (direction) => {
  const newDate = new Date(currentMonday.value)
  newDate.setDate(newDate.getDate() + (direction * 7))
  currentMonday.value = newDate
}

const goToToday = () => {
  currentMonday.value = getMonday(new Date())
}

// --- Lifecycle & Watchers ---
onMounted(fetchData)
watch(currentMonday, fetchData)

</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900 font-sans selection:bg-indigo-100 p-4 md:p-8">
    <div class="max-w-2xl mx-auto space-y-8">
      
      <!-- Header / Nav -->
      <header class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-bold tracking-tight text-slate-900 flex items-center gap-2">
            <TrendingUp class="text-indigo-600 h-8 w-8" />
            Chore Tracker
          </h1>
          <p class="text-slate-500 mt-1">Weekly roommate rotation system</p>
        </div>
        <div class="flex items-center bg-white rounded-xl shadow-sm border border-slate-200 p-1">
          <button 
            @click="navigateWeek(-1)"
            class="p-2 hover:bg-slate-50 rounded-lg transition-colors text-slate-600"
          >
            <ChevronLeft class="h-5 w-5" />
          </button>
          <button 
            @click="goToToday"
            class="px-4 py-1.5 text-sm font-medium text-slate-700 hover:text-indigo-600 transition-colors"
          >
            {{ isCurrentWeek ? 'This Week' : 'Back to Today' }}
          </button>
          <button 
            @click="navigateWeek(1)"
            class="p-2 hover:bg-slate-50 rounded-lg transition-colors text-slate-600"
          >
            <ChevronRight class="h-5 w-5" />
          </button>
        </div>
      </header>

      <!-- Main Hero Card -->
      <main v-if="!loading" class="relative">
        <div 
          class="bg-white rounded-3xl shadow-xl shadow-indigo-100/50 border border-slate-100 overflow-hidden transition-all duration-300 hover:shadow-2xl hover:shadow-indigo-200/50"
          :class="{ 'opacity-50 pointer-events-none': syncing }"
        >
          <!-- Card Top Accent -->
          <div class="h-2 bg-gradient-to-r from-indigo-500 via-purple-500 to-indigo-500"></div>
          
          <div class="p-8 md:p-10 space-y-8">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2 text-slate-400 font-medium text-sm tracking-wider uppercase">
                <Calendar class="h-4 w-4" />
                {{ formatDate(currentMonday) }}
              </div>
              <div 
                class="px-3 py-1 rounded-full text-xs font-bold uppercase tracking-widest border"
                :class="rotationEntry?.is_completed 
                  ? 'bg-emerald-50 text-emerald-600 border-emerald-100' 
                  : 'bg-amber-50 text-amber-600 border-amber-100'"
              >
                {{ rotationEntry?.is_completed ? 'Completed' : 'Pending' }}
              </div>
            </div>

            <div class="flex flex-col items-center text-center space-y-4">
              <div class="relative group">
                <div class="absolute -inset-1 bg-gradient-to-r from-indigo-500 to-purple-500 rounded-full blur opacity-25 group-hover:opacity-50 transition duration-1000 group-hover:duration-200"></div>
                <div class="relative h-24 w-24 rounded-full bg-slate-100 border-4 border-white shadow-lg overflow-hidden flex items-center justify-center">
                  <img 
                    v-if="currentCleaner?.avatar_url" 
                    :src="currentCleaner.avatar_url" 
                    class="h-full w-full object-cover"
                  >
                  <UserIcon v-else class="h-12 w-12 text-slate-300" />
                </div>
              </div>
              
              <div class="space-y-1">
                <p class="text-lg font-medium text-slate-500">Cleaner of the Week</p>
                <h2 class="text-4xl font-extrabold text-slate-900 tracking-tight">
                  {{ currentCleaner?.name || 'Loading...' }}
                </h2>
                <p v-if="rotationEntry?.swapped_from_id" class="text-sm text-indigo-500 font-medium">
                  (Swapped Turn)
                </p>
              </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-4">
              <button 
                @click="toggleComplete"
                class="flex items-center justify-center gap-2 px-6 py-4 rounded-2xl font-bold transition-all active:scale-95 shadow-sm"
                :class="rotationEntry?.is_completed 
                  ? 'bg-slate-100 text-slate-600 hover:bg-slate-200' 
                  : 'bg-indigo-600 text-white hover:bg-indigo-700 shadow-indigo-200'"
              >
                <CheckCircle2 v-if="rotationEntry?.is_completed" class="h-5 w-5" />
                <Circle v-else class="h-5 w-5" />
                {{ rotationEntry?.is_completed ? 'Mark Unfinished' : 'Mark as Done' }}
              </button>
              
              <button 
                @click="showSwapModal = true"
                class="flex items-center justify-center gap-2 px-6 py-4 rounded-2xl border-2 border-slate-100 text-slate-600 font-bold hover:bg-slate-50 hover:border-slate-200 transition-all active:scale-95"
              >
                <ArrowLeftRight class="h-5 w-5" />
                Swap Turn
              </button>
            </div>
          </div>
        </div>

        <!-- Loading Overlay -->
        <div v-if="syncing" class="absolute inset-0 flex items-center justify-center z-10">
          <div class="bg-white/80 backdrop-blur-sm p-4 rounded-2xl shadow-xl flex items-center gap-3">
            <Loader2 class="h-6 w-6 text-indigo-600 animate-spin" />
            <span class="font-bold text-slate-700">Syncing...</span>
          </div>
        </div>
      </main>

      <!-- Daily Cooking Schedule -->
      <section v-if="!loading" class="space-y-4 animate-in" style="animation-delay: 100ms">
        <h3 class="text-sm font-bold uppercase tracking-widest text-slate-400 flex items-center gap-2">
          <ChefIcon class="h-4 w-4" />
          Weekday Cooking
        </h3>
        <div class="bg-indigo-900 rounded-3xl p-6 shadow-xl shadow-indigo-900/20 text-white overflow-hidden relative">
          <!-- Background Decoration -->
          <div class="absolute top-0 right-0 -mr-8 -mt-8 h-32 w-32 bg-indigo-500/10 rounded-full blur-3xl"></div>
          
          <div class="grid grid-cols-1 divide-y divide-indigo-800/50">
            <div 
              v-for="(item, idx) in cookingSchedule" 
              :key="idx"
              class="flex items-center justify-between py-3 first:pt-0 last:pb-0 group"
            >
              <div class="flex items-center gap-3">
                <span class="w-24 text-indigo-300 font-medium text-sm">{{ item.day }}</span>
                <div class="h-8 w-8 rounded-full bg-indigo-800 flex items-center justify-center overflow-hidden border border-indigo-700/50">
                  <img v-if="item.chef?.avatar_url" :src="item.chef.avatar_url">
                  <UserIcon v-else class="h-4 w-4 text-indigo-400" />
                </div>
                <span class="font-bold tracking-tight">{{ item.chef?.name }}</span>
              </div>
              <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-widest text-indigo-400/80">
                <Clock class="h-3 w-3" />
                Dinner
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Skeleton Loading for Cooking -->
      <!-- <div v-else class="h-64 bg-slate-100 rounded-3xl animate-pulse"></div> -->

      <!-- Skeleton Loading -->
      <div v-else class="bg-white rounded-3xl shadow-xl border border-slate-100 p-8 md:p-10 space-y-8 animate-pulse">
        <div class="flex justify-between">
          <div class="h-4 w-32 bg-slate-100 rounded"></div>
          <div class="h-6 w-20 bg-slate-100 rounded-full"></div>
        </div>
        <div class="flex flex-col items-center space-y-4">
          <div class="h-24 w-24 rounded-full bg-slate-100"></div>
          <div class="h-4 w-24 bg-slate-100 rounded"></div>
          <div class="h-10 w-48 bg-slate-100 rounded"></div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="h-14 bg-slate-100 rounded-2xl"></div>
          <div class="h-14 bg-slate-100 rounded-2xl"></div>
        </div>
      </div>

      <!-- Upcoming Schedule -->
      <section class="space-y-4">
        <h3 class="text-sm font-bold uppercase tracking-widest text-slate-400 flex items-center gap-2">
          Upcoming Schedule
        </h3>
        <div class="grid gap-3">
          <div 
            v-for="(item, idx) in upcomingSchedule" 
            :key="idx"
            class="group bg-white p-4 rounded-2xl border border-slate-100 flex items-center justify-between transition-all hover:shadow-md hover:border-indigo-100"
          >
            <div class="flex items-center gap-4">
              <div class="h-10 w-10 rounded-full bg-slate-50 flex items-center justify-center border border-slate-100 group-hover:border-indigo-100 transition-colors">
                 <UserIcon class="h-5 w-5 text-slate-400 group-hover:text-indigo-400" />
              </div>
              <div>
                <p class="font-bold text-slate-900 leading-tight group-hover:text-indigo-600 transition-colors">{{ item.cleaner?.name }}</p>
                <div class="flex items-center gap-2">
                  <p class="text-xs font-medium text-slate-400">{{ formatDate(item.date) }}</p>
                  <span v-if="item.isSwapped" class="text-[10px] font-bold text-indigo-500 bg-indigo-50 px-1.5 py-0.5 rounded uppercase">Swapped</span>
                </div>
              </div>
            </div>
            <div class="text-xs font-bold text-slate-300 uppercase italic">
              Week +{{ idx + 1 }}
            </div>
          </div>
        </div>
      </section>

      <!-- Swap Modal (Simplified for UI requirements) -->
      <div v-if="showSwapModal" class="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center p-4">
        <div class="bg-white w-full max-w-sm rounded-[2rem] shadow-2xl overflow-hidden p-6 space-y-6 animate-in slide-in-from-bottom duration-300">
          <div class="text-center space-y-2">
            <h4 class="text-2xl font-extrabold text-slate-900 italic">Swap Turn</h4>
            <p class="text-slate-500">Who should clean this week instead of {{ currentCleaner?.name }}?</p>
          </div>
          
          <div class="grid gap-2">
            <button 
              v-for="rm in roommates.filter(r => r.id !== currentCleaner?.id)" 
              :key="rm.id"
              @click="swapCleaner(rm.id)"
              class="flex items-center gap-4 p-4 rounded-2xl border border-slate-100 hover:bg-indigo-50 hover:border-indigo-100 transition-all text-left"
            >
              <div class="h-10 w-10 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 overflow-hidden">
                <img v-if="rm.avatar_url" :src="rm.avatar_url">
                <UserIcon v-else class="h-5 w-5" />
              </div>
              <span class="font-bold text-slate-700">{{ rm.name }}</span>
            </button>
          </div>
          
          <button 
            @click="showSwapModal = false"
            class="w-full py-4 rounded-2xl font-bold text-slate-400 hover:text-slate-600 transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>

    </div>
  </div>
</template>

<style>
/* Custom animations & refinements */
.animate-in {
  animation-name: slideUp;
  animation-fill-mode: forwards;
}

@keyframes slideUp {
  from { transform: translateY(20px); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
</style>
