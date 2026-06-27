// Command dashboard generates the "Indoor vs Outdoor" Grafana dashboard JSON.
//
// It overlays AirGradient indoor sensor metrics (airgradient_*) against the
// outdoor metrics produced by the outdoor-weather exporter (outdoor_*), so the
// two can be compared directly. Run with:
//
//	go run . > ../ytt/dashboard.json
//
// The source lives in the homelab repo for now but is intentionally written in
// the same grafana-foundation-sdk style as the public airgradient-exporter
// dashboard, so it can be folded into that codebase later.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/grafana/grafana-foundation-sdk/go/cog"
	"github.com/grafana/grafana-foundation-sdk/go/common"
	"github.com/grafana/grafana-foundation-sdk/go/dashboard"
	"github.com/grafana/grafana-foundation-sdk/go/prometheus"
	"github.com/grafana/grafana-foundation-sdk/go/timeseries"
)

// comparePanel describes one indoor/outdoor overlay panel.
type comparePanel struct {
	title    string
	unit     string
	desc     string
	indoor   string // PromQL expr; empty = outdoor-only panel
	outdoor  []outdoorSeries
	softMinZ bool // clamp axis soft min to 0
}

type outdoorSeries struct {
	expr   string
	legend string
}

func indoor(metric string) string {
	return fmt.Sprintf(`avg by(serialno) (%s{serialno=~"$serialno"})`, metric)
}

var panels = []comparePanel{
	{
		title:   "Temperature — Indoor vs Outdoor",
		unit:    "celsius",
		desc:    "Indoor AirGradient ambient temperature vs outdoor temperature at the configured coordinates (Open-Meteo).",
		indoor:  indoor("airgradient_atmp"),
		outdoor: []outdoorSeries{{`outdoor_temp_celsius`, "Outdoor"}},
	},
	{
		title:   "Relative Humidity — Indoor vs Outdoor",
		unit:    "percent",
		desc:    "Indoor vs outdoor relative humidity.",
		indoor:  indoor("airgradient_rhum"),
		outdoor: []outdoorSeries{{`outdoor_humidity_percent`, "Outdoor"}},
	},
	{
		title:    "PM2.5 — Indoor vs Outdoor",
		unit:     "conμgm3",
		desc:     "Indoor AirGradient PM2.5 vs nearest outdoor sensor station (UBA).",
		indoor:   indoor("airgradient_pm02"),
		outdoor:  []outdoorSeries{{`outdoor_pm02_ugm3`, "Outdoor (UBA)"}},
		softMinZ: true,
	},
	{
		title:    "PM10 — Indoor vs Outdoor",
		unit:     "conμgm3",
		desc:     "Indoor AirGradient PM10 vs nearest outdoor sensor station (UBA).",
		indoor:   indoor("airgradient_pm10"),
		outdoor:  []outdoorSeries{{`outdoor_pm10_ugm3`, "Outdoor (UBA)"}},
		softMinZ: true,
	},
	{
		title: "Outdoor Air Quality (NO₂ / O₃)",
		unit:  "conμgm3",
		desc:  "Outdoor-only nitrogen dioxide and ozone from the nearest UBA sensor station.",
		outdoor: []outdoorSeries{
			{`outdoor_no2_ugm3`, "NO₂"},
			{`outdoor_o3_ugm3`, "O₃"},
		},
		softMinZ: true,
	},
	{
		title:    "Outdoor Wind Speed",
		unit:     "velocityms",
		desc:     "Outdoor-only wind speed at 10 m (Open-Meteo).",
		outdoor:  []outdoorSeries{{`outdoor_wind_speed_ms`, "Wind"}},
		softMinZ: true,
	},
	{
		title:   "Outdoor Surface Pressure",
		unit:    "pressurehpa",
		desc:    "Outdoor-only surface atmospheric pressure (Open-Meteo).",
		outdoor: []outdoorSeries{{`outdoor_pressure_hpa`, "Pressure"}},
	},
	{
		title:    "Outdoor Precipitation",
		unit:     "lengthmm",
		desc:     "Outdoor-only hourly precipitation (Open-Meteo).",
		outdoor:  []outdoorSeries{{`outdoor_precip_mm`, "Precip"}},
		softMinZ: true,
	},
}

func buildDashboard() (dashboard.Dashboard, error) {
	builder := dashboard.NewDashboardBuilder("Indoor vs Outdoor").
		Uid("outdoor-weather-compare").
		Description("Compares AirGradient indoor air quality against outdoor weather (Open-Meteo) and air quality (UBA).").
		Tags([]string{"airgradient", "outdoor", "weather"}).
		Editable().
		Tooltip(dashboard.DashboardCursorSyncCrosshair).
		Time("now-90d", "now").
		Refresh("5m").
		WithVariable(buildSerialNoVariable())

	var y uint32
	for i, p := range panels {
		if i > 0 && i%2 == 0 {
			y += 9
		}
		x := uint32((i % 2) * 12)
		builder = builder.WithPanel(buildPanel(p, dashboard.GridPos{H: 9, W: 12, X: x, Y: y}))
	}

	return builder.Build()
}

func buildSerialNoVariable() *dashboard.QueryVariableBuilder {
	return dashboard.NewQueryVariableBuilder("serialno").
		Datasource(prometheusDatasourceRef()).
		Query(dashboard.StringOrMap{
			String: cog.ToPtr("label_values(airgradient_config_info,serialno)"),
		}).
		AllValue(".*").
		IncludeAll(true).
		Multi(true).
		Refresh(dashboard.VariableRefreshOnDashboardLoad).
		Sort(dashboard.VariableSortAlphabeticalAsc)
}

func buildPanel(p comparePanel, pos dashboard.GridPos) *timeseries.PanelBuilder {
	b := timeseries.NewPanelBuilder().
		Title(p.title).
		Description(p.desc).
		Unit(p.unit).
		GridPos(pos).
		Datasource(prometheusDatasourceRef()).
		LineWidth(2).
		FillOpacity(10).
		LineInterpolation(common.LineInterpolationSmooth).
		ShowPoints(common.VisibilityModeNever).
		SpanNulls(common.BoolOrFloat64{Bool: cog.ToPtr(true)}).
		Legend(
			common.NewVizLegendOptionsBuilder().
				DisplayMode(common.LegendDisplayModeTable).
				Placement(common.LegendPlacementBottom).
				ShowLegend(true).
				Calcs([]string{"lastNotNull", "min", "max", "mean"}),
		).
		Tooltip(
			common.NewVizTooltipOptionsBuilder().
				Mode(common.TooltipDisplayModeMulti).
				Sort(common.SortOrderDescending),
		)

	if p.softMinZ {
		b = b.AxisSoftMin(0)
	}
	if p.indoor != "" {
		b = b.WithTarget(prometheusQuery(p.indoor, "Indoor {{serialno}}"))
	}
	for _, o := range p.outdoor {
		// Merge provenance sources (archive/forecast/live) and station into one
		// line; at any timestamp only one source has data for a given metric.
		expr := fmt.Sprintf("avg (%s)", o.expr)
		b = b.WithTarget(prometheusQuery(expr, o.legend))
	}
	return b
}

func prometheusDatasourceRef() dashboard.DataSourceRef {
	return dashboard.DataSourceRef{Type: cog.ToPtr("prometheus")}
}

func prometheusQuery(expr, legend string) *prometheus.DataqueryBuilder {
	return prometheus.NewDataqueryBuilder().
		Expr(expr).
		LegendFormat(legend).
		EditorMode(prometheus.QueryEditorModeCode)
}

func main() {
	dash, err := buildDashboard()
	if err != nil {
		fmt.Fprintf(os.Stderr, "build dashboard: %v\n", err)
		os.Exit(1)
	}
	out, err := json.MarshalIndent(dash, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(string(out))
}
