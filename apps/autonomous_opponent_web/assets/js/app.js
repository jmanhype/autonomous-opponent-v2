// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Hooks for LiveView components
let Hooks = {
  // Pattern Analytics Chart Hook
  PatternChart: {
    mounted() {
      this.chart = null
      this.initChart()
      
      // Listen for data updates from server
      this.handleEvent("update_chart", ({data}) => {
        this.updateChart(data)
      })
    },
    
    destroyed() {
      if (this.chart) {
        // Clean up chart instance
        this.chart = null
      }
    },
    
    initChart() {
      const canvas = this.el
      const ctx = canvas.getContext('2d')
      
      // Simple line chart rendering
      this.chart = {
        ctx: ctx,
        width: canvas.width,
        height: canvas.height,
        data: []
      }
      
      this.render()
    },
    
    updateChart(newData) {
      if (!this.chart) return
      
      this.chart.data = newData
      this.render()
    },
    
    render() {
      if (!this.chart || !this.chart.data.length) return
      
      const {ctx, width, height, data} = this.chart
      
      // Clear canvas
      ctx.clearRect(0, 0, width, height)
      
      // Simple line chart
      ctx.strokeStyle = '#3b82f6'
      ctx.lineWidth = 2
      ctx.beginPath()
      
      const xStep = width / (data.length - 1)
      const maxValue = Math.max(...data.map(d => d.value))
      const yScale = (height - 20) / maxValue
      
      data.forEach((point, index) => {
        const x = index * xStep
        const y = height - (point.value * yScale) - 10
        
        if (index === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      })
      
      ctx.stroke()
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket