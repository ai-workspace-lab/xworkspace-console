import type { Labels, NavItem, PortalService, RuntimeMetrics, Service } from '@/lib/data';
import { ArchPipeline } from './ArchPipeline';

export function WorkspaceHome({
  labels,
  services,
  metrics,
  portalServices,
  onOpenService,
}: {
  labels: Labels;
  services: Service[];
  metrics: RuntimeMetrics;
  portalServices: PortalService[];
  onOpenService: (item: NavItem) => void;
}) {
  return (
    <div className="workspace-body home-body">
      <section className="console-board">
        <div className="command-panel">
          <div className="board-heading">
            <div>
              <h1>{labels.homepageTitle}</h1>
              <p>{labels.homepageSubtitle}</p>
            </div>
          </div>

          <ArchPipeline labels={labels} services={services} metrics={metrics} portalServices={portalServices} onOpenService={onOpenService} />
        </div>
      </section>
    </div>
  );
}
